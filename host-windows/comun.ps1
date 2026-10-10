Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Raiz = Split-Path $PSScriptRoot -Parent
$script:EnvPath = Join-Path $script:Raiz '.env'
$script:ComposeBase = @('compose', '--project-directory', $script:Raiz, '--env-file', $script:EnvPath, '-f', (Join-Path $script:Raiz 'docker-compose.yml'), '-f', (Join-Path $script:Raiz 'docker-compose.windows.yml'))

function Mensaje([string]$Tipo, [string]$Texto) { Write-Host "[$Tipo] $Texto" }
function Test-IPv4([string]$IP) {
    if ($IP -notmatch '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$') { return $false }
    return @($IP.Split('.') | Where-Object { [int]$_ -gt 255 }).Count -eq 0
}
function Get-RangoIPv4([string]$IP) {
    if (!(Test-IPv4 $IP)) { return 'Invalida' }
    $p = @($IP.Split('.') | ForEach-Object { [int]$_ })
    if ($p[0] -eq 100 -and $p[1] -ge 64 -and $p[1] -le 127) { return 'CGNAT' }
    if ($p[0] -eq 10 -or ($p[0] -eq 172 -and $p[1] -ge 16 -and $p[1] -le 31) -or ($p[0] -eq 192 -and $p[1] -eq 168)) { return 'Privada' }
    if ($p[0] -eq 127) { return 'Loopback' }
    if ($p[0] -eq 169 -and $p[1] -eq 254) { return 'LinkLocal' }
    if ($p[0] -eq 0 -or $p[0] -ge 224 -or ($p[0] -eq 192 -and $p[1] -eq 0 -and $p[2] -le 2) -or ($p[0] -eq 198 -and $p[1] -in 18,19) -or ($p[0] -eq 198 -and $p[1] -eq 51 -and $p[2] -eq 100) -or ($p[0] -eq 203 -and $p[1] -eq 0 -and $p[2] -eq 113)) { return 'Reservada' }
    return 'Publica'
}
function Get-Sslip([string]$IP) {
    if ((Get-RangoIPv4 $IP) -ne 'Publica') { throw 'sslip.io requiere una IPv4 publica enrutable.' }
    return "$($IP.Replace('.', '-')).sslip.io"
}
function Test-Dominio([string]$Dominio) {
    return $Dominio.Length -le 253 -and $Dominio.Contains('.') -and $Dominio -notmatch '^[0-9.]+$' -and $Dominio -match '^(?=.{1,253}$)([a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
}
function Get-Cgnat([string]$LAN, [string]$Publica, [string]$WAN = '') {
    if ($WAN) {
        $rango = Get-RangoIPv4 $WAN
        if ($rango -eq 'Invalida') { throw 'La WAN del router debe ser IPv4.' }
        if ($rango -eq 'CGNAT') { return 'Probable CGNAT: WAN en 100.64.0.0/10.' }
        if ($rango -ne 'Publica') { return 'Probable doble NAT/CGNAT: WAN privada o no enrutable.' }
        if ($Publica -and $WAN -ne $Publica) { return 'Posible NAT del ISP, VPN o doble NAT: WAN diferente de la IP HTTP.' }
        return 'No detectado: WAN coincide con IP publica (no concluyente).'
    }
    if ((Get-RangoIPv4 $LAN) -eq 'CGNAT') { return 'Probable CGNAT: adaptador en 100.64.0.0/10.' }
    return 'Indeterminado: no se puede leer la WAN del router automaticamente. Comparala con la IP publica; LAN privada es normal y no prueba CGNAT.'
}
function Read-Env([string]$Path = $script:EnvPath) {
    $result = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $key = $Matches[1]; $value = $Matches[2].Trim()
                if ($value -match "^'(.*)'\s*(?:#.*)?$") { $value = $Matches[1].Replace("\'", "'") }
                elseif ($value -match '^"(.*)"\s*(?:#.*)?$') { $value = $Matches[1].Replace('\"', '"').Replace('$$', '$') }
                else { $value = ($value -replace '\s+#.*$', '').Trim() }
                $result[$key] = $value
            }
        }
    }
    return $result
}
function Write-Env([hashtable]$Cambios, [string]$Path = $script:EnvPath) {
    $lines = @(); if (Test-Path -LiteralPath $Path) { $lines = @([IO.File]::ReadAllLines($Path)) }
    $seen = @{}; $result = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=' -and $Cambios.ContainsKey($Matches[1])) {
            $key = $Matches[1]
            if (!$seen[$key]) {
                $value = [string]$Cambios[$key]
                if ($value -match '[\r\n\x00]') { throw "Valor multilinea no permitido: $key" }
                $result += Format-EnvLine $key $value
                $seen[$key] = $true
            }
        } else { $result += $line }
    }
    foreach ($key in ($Cambios.Keys | Sort-Object)) {
        $value = [string]$Cambios[$key]
        if ($value -match '[\r\n\x00]') { throw "Valor multilinea no permitido: $key" }
        if (!$seen[$key]) { $result += Format-EnvLine $key $value }
    }
    $tmp = "$Path.sla-tmp"
    [IO.File]::WriteAllText($tmp, (($result -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Format-EnvLine([string]$Key, [string]$Value) {
    # Los valores simples mantienen el formato de start.sh; quoting literal para secretos.
    if ($Value -match '^[a-zA-Z0-9_./:, -]*$') { return "$Key=$Value" }
    return "$Key='$($Value.Replace("'", "\'"))'"
}
function New-Secreto {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Get-OnlineEnv([hashtable]$Actual, [string]$IP, [string]$Dominio = '') {
    if ((Get-RangoIPv4 $IP) -ne 'Publica') { throw 'No se obtuvo una IPv4 publica valida.' }
    if (!$Dominio) { $Dominio = $Actual['DOMINIO']; if (!$Dominio -or $Dominio -like '*.sslip.io') { $Dominio = Get-Sslip $IP } }
    if (!(Test-Dominio $Dominio)) { throw 'Dominio invalido. Usa un hostname, sin https, rutas ni puertos.' }
    $c = @{ MODO='online'; BIND_WEB='127.0.0.1'; BIND_UDP='0.0.0.0'; IP_PUBLICA=$IP; URL_JUEGO="https://$Dominio"; DOMINIO=$Dominio; DOMINIO_CADDY=$Dominio; CONFIAR_PROXY='1'; HOST_UID='10001:10001' }
    $defaults = @{ RCON_PASSWORD=(New-Secreto); CLAVE_ESTADISTICAS=(New-Secreto); NOMBRE_SERVIDOR='SLA - Counter-Strike 1.6'; MAPA='de_dust2'; MAX_JUGADORES='12'; BOTS='4'; BOTS_DIFICULTAD='0'; ARCHIVOS='propios'; MAX_POR_IP='4' }
    foreach ($key in $defaults.Keys) { if (!$Actual[$key]) { $c[$key] = $defaults[$key] } }
    # Normalizar quoting de claves sin regenerarlas (Compose no interpola comillas simples).
    foreach ($key in 'RCON_PASSWORD','CLAVE_ESTADISTICAS','CONTRASENA') { if ($Actual[$key]) { $c[$key] = $Actual[$key] } }
    # Pasar de local a publico nunca distribuye archivos Valve sin contrasena.
    if ($Actual['ARCHIVOS'] -eq 'servidor' -and !$Actual['CONTRASENA']) { $c['ARCHIVOS'] = 'propios' }
    if ($Actual['ARCHIVOS'] -and $Actual['ARCHIVOS'] -notin 'servidor','propios') { throw 'ARCHIVOS debe ser propios o servidor.' }
    if ($Actual['MAX_POR_IP'] -and ($Actual['MAX_POR_IP'] -notmatch '^\d+$' -or [int]$Actual['MAX_POR_IP'] -lt 1)) { throw 'MAX_POR_IP debe ser positivo para hosting publico.' }
    return $c
}
function Assert-Windows {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Este script requiere Windows 11/10 y Docker Desktop con contenedores Linux.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
function Invoke-Docker([string[]]$Argumentos, [switch]$Capturar) {
    # PS 5.1 convierte stderr nativo en ErrorRecord; comprobar exit code nosotros.
    $ErrorActionPreference = 'Continue'
    if ($Capturar) { $output = & docker @Argumentos 2>&1; if ($LASTEXITCODE -ne 0) { throw "Docker fallo: $($output -join ' ')" }; return ($output -join "`n") }
    & docker @Argumentos
    if ($LASTEXITCODE -ne 0) { throw "Docker fallo (codigo $LASTEXITCODE): $($Argumentos -join ' ')" }
}
function Invoke-Compose([string[]]$Argumentos, [switch]$Capturar) { Invoke-Docker ($script:ComposeBase + @('--profile','online') + $Argumentos) -Capturar:$Capturar }
function Ensure-Docker {
    $ErrorActionPreference = 'Continue'
    if (!(Get-Command docker -ErrorAction SilentlyContinue)) {
        $bin = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
        if (Test-Path -LiteralPath (Join-Path $bin 'docker.exe')) { $env:PATH = "$bin;$env:PATH" }
        else { throw 'Falta Docker Desktop. Instala https://www.docker.com/products/docker-desktop/ y abrilo una vez (backend WSL2 y contenedores Linux). No hace falta instalar Ubuntu.' }
    }
    $endpoint = $env:DOCKER_HOST
    if (!$endpoint) { $endpoint = Invoke-Docker @('context','inspect','--format','{{.Endpoints.docker.Host}}') -Capturar }
    if ($endpoint -notmatch '^npipe:/{2,}\./pipe/') { throw 'El contexto Docker no apunta al motor local Windows por named pipe. Selecciona Docker Desktop (docker context use desktop-linux) y retira DOCKER_HOST remoto.' }
    & docker info --format '{{.OSType}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (!(Test-Path -LiteralPath $desktop)) { throw 'No encuentro Docker Desktop. Abrilo manualmente y vuelve a ejecutar.' }
        Mensaje INFO 'Abriendo Docker Desktop; espero hasta 180 segundos.'
        Start-Process -FilePath $desktop -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(180)
        do {
            Start-Sleep -Seconds 3
            & docker info --format '{{.OSType}}' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
        } while ((Get-Date) -lt $deadline)
        if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop no arranco. Revisa WSL2, virtualizacion y la pantalla de Docker Desktop.' }
    }
    $os = Invoke-Docker @('info','--format','{{.OSType}}') -Capturar
    if ($os.Trim() -ne 'linux') { throw 'Cambia Docker Desktop a Linux containers.' }
    $version = Invoke-Docker @('compose','version','--short') -Capturar
    if ($version.TrimStart('v') -notmatch '^(\d+)\.(\d+)') { throw 'No pude leer la version de Compose.' }
    if ([int]$Matches[1] -lt 2 -or ([int]$Matches[1] -eq 2 -and [int]$Matches[2] -lt 24)) { throw 'Actualiza Docker Desktop: requiere Compose >= 2.24.4 para !override.' }
    if ($version.TrimStart('v') -match '^2\.24\.(\d+)' -and [int]$Matches[1] -lt 4) { throw 'Requiere Compose >= 2.24.4.' }
    Mensaje OK "Docker Linux y Compose $version"
}
function Get-Red([string]$SeleccionIP = '') {
    $candidates = @()
    foreach ($route in @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Where-Object { $_.NextHop -ne '0.0.0.0' })) {
        $iface = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.ifIndex -eq $route.InterfaceIndex } | Select-Object -First 1
        foreach ($ip in @(Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex | Where-Object { $_.AddressState -eq 'Preferred' -and !$_.SkipAsSource })) {
            if ($SeleccionIP -and $ip.IPAddress -ne $SeleccionIP) { continue }
            if ((Get-RangoIPv4 $ip.IPAddress) -in 'Loopback','LinkLocal','Invalida') { continue }
            $candidates += [pscustomobject]@{ LAN=$ip.IPAddress; Gateway=$route.NextHop; MAC=$(if ($adapter) { $adapter.MacAddress } else { '?' }); DHCP=[string]$iface.Dhcp; Adaptador=[string]$iface.InterfaceAlias; Metrica=([int]$route.RouteMetric + [int]$iface.InterfaceMetric) }
        }
    }
    $red = $candidates | Sort-Object Metrica | Select-Object -First 1
    if (!$red) { throw 'No encontre adaptador IPv4 con gateway. Revisa la red o especifica -IPLan.' }
    return $red
}
function Get-PublicIP {
    foreach ($url in @('https://api.ipify.org','https://checkip.amazonaws.com')) {
        try {
            $ip = ([string](Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8).Content).Trim()
            if ((Get-RangoIPv4 $ip) -eq 'Publica') { return $ip }
        } catch { }
    }
    throw 'No pude detectar IPv4 publica. Revisa Internet/VPN o usa -IPPublica con tu IPv4 real.'
}
function Get-Reglas {
    foreach ($pair in @(@('TCP',80),@('TCP',443),@('UDP',443),@('UDP',27018))) {
        [pscustomobject]@{ Name="SLA-CS16-$($pair[0])-$($pair[1])"; DisplayName="SLA-CS16 $($pair[0]) $($pair[1])"; Protocol=$pair[0]; Port=$pair[1]; Group='SLA-CS16 Public Host' }
    }
}
function Assert-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Esta opcion requiere PowerShell como administrador. Vuelve a ejecutar con el mismo flag en una terminal elevada.' }
}
function Set-Firewall([switch]$Eliminar) {
    Assert-Admin
    foreach ($r in Get-Reglas) {
        $existing = Get-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
        if ($existing -and $existing.Group -ne $r.Group) { throw "Regla ajena con el nombre $($r.Name); no la modifico." }
        if ($Eliminar) { if ($existing) { $existing | Remove-NetFirewallRule }; continue }
        if ($existing) {
            $existing | Set-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -Profile Any
            $existing | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol $r.Protocol -LocalPort $r.Port
        } else {
            New-NetFirewallRule -Name $r.Name -DisplayName $r.DisplayName -Group $r.Group -Direction Inbound -Action Allow -Protocol $r.Protocol -LocalPort $r.Port -Profile Any | Out-Null
        }
    }
    Mensaje OK $(if ($Eliminar) { 'Reglas SLA-CS16 eliminadas.' } else { 'Firewall configurado sin duplicar reglas.' })
}
function Convert-DockerPs([string]$Texto) {
    if (!$Texto.Trim()) { return @() }
    if ($Texto.TrimStart().StartsWith('[')) { return @(ConvertFrom-Json $Texto) }
    return @($Texto -split '\r?\n' | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-Json $_ })
}
function Get-Publicaciones {
    $json = Invoke-Compose @('config','--format','json') -Capturar
    $config = ConvertFrom-Json $json
    foreach ($service in $config.services.PSObject.Properties) {
        $ports = $service.Value.PSObject.Properties['ports']
        if (!$ports) { continue }
        foreach ($p in $ports.Value) { [pscustomobject]@{ Servicio=$service.Name; IP=[string]$p.host_ip; Puerto=[int]$p.published; Destino=[int]$p.target; Protocolo=[string]$p.protocol } }
    }
}
function Assert-Publicaciones {
    $ports = @(Get-Publicaciones)
    $expected = @('caddy/TCP/80/80','caddy/TCP/443/443','caddy/UDP/443/443','web/UDP/27018/27018')
    $actual = @($ports | Where-Object { $_.IP -ne '127.0.0.1' } | ForEach-Object { "$($_.Servicio)/$($_.Protocolo.ToUpper())/$($_.Puerto)/$($_.Destino)" })
    if (@(Compare-Object $expected $actual).Count) { throw 'Compose publica puertos inesperados; no arranco. Revisa los overrides.' }
    foreach ($p in $ports | Where-Object { $_.IP -eq '127.0.0.1' }) {
        if (!(($p.Servicio -eq 'web' -and $p.Puerto -eq 27016) -or ($p.Servicio -eq 'studio' -and $p.Puerto -eq 27080))) { throw 'Puerto local inesperado.' }
    }
}
function Test-PuertosLibres {
    # Docker puede no aparecer en Get-NetUDPEndpoint: verificar tambien sockets.
    $running = Convert-DockerPs (Invoke-Compose @('ps','--format','json') -Capturar)
    $owned = @{}
    foreach ($c in $running) {
        if ($c.State -ne 'running') { continue }
        if (!$c.PSObject.Properties['Publishers']) { continue }
        foreach ($p in $c.Publishers) { $owned["$($p.Protocol)/$($p.PublishedPort)"] = $true }
    }
    foreach ($p in Get-Publicaciones) {
        $key = "$($p.Protocolo)/$($p.Puerto)"
        if ($owned[$key]) { Mensaje OK "$key publicado por este proyecto"; continue }
        $socket = New-Object Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork, $(if ($p.Protocolo -eq 'tcp') { [Net.Sockets.SocketType]::Stream } else { [Net.Sockets.SocketType]::Dgram }), $(if ($p.Protocolo -eq 'tcp') { [Net.Sockets.ProtocolType]::Tcp } else { [Net.Sockets.ProtocolType]::Udp }))
        try {
            $socket.ExclusiveAddressUse = $true
            $address = '0.0.0.0'; if ($p.IP) { $address = $p.IP }
            $socket.Bind((New-Object Net.IPEndPoint([Net.IPAddress]::Parse($address), $p.Puerto)))
            Mensaje OK "$key disponible"
        } catch { throw "Puerto $key ocupado o reservado por Windows: $($_.Exception.Message)" }
        finally { $socket.Dispose() }
    }
}
function Initialize-Archivos {
    $e = Read-Env
    foreach ($dir in @('build','build/descarga','texturas','mapas','metricas')) { New-Item -ItemType Directory -Path (Join-Path $script:Raiz $dir) -Force | Out-Null }
    $salas = Join-Path $script:Raiz 'config/salas.conf'
    if (!(Test-Path -LiteralPath $salas) -or (Get-Item -LiteralPath $salas).Length -eq 0) {
        [IO.File]::WriteAllText($salas, "# id | nombre | mapa | jugadores | bots | dificultad`n1 | SLA Clasico | de_dust2 | 12 | 4 | 1`n2 | SLA Inferno | de_inferno | 12 | 2 | 2`n3 | SLA Solo humanos | de_dust2 | 12 | 0 | 0`n", (New-Object Text.UTF8Encoding($false)))
    }
    $template = [IO.File]::ReadAllText((Join-Path $script:Raiz 'config/server.cfg.template'))
    foreach ($pair in @(@('RCON','RCON_PASSWORD'),@('NOMBRE','NOMBRE_SERVIDOR'),@('CONTRASENA','CONTRASENA'))) {
        $safe = ([string]$e[$pair[1]]) -replace '["\\/&;|\r\n]', ''
        if ($pair[0] -ne 'NOMBRE' -and $safe -ne [string]$e[$pair[1]]) { throw "$($pair[1]) contiene caracteres incompatibles con server.cfg." }
        $template = $template.Replace("{{$($pair[0])}}", $safe)
    }
    $template = $template.Replace('{{CHEATS}}','0')
    [IO.File]::WriteAllText((Join-Path $script:Raiz 'config/server.cfg'), $template, (New-Object Text.UTF8Encoding($false)))
}
function Test-Juego([string]$Dir) {
    foreach ($file in @('valve/delta.lst','cstrike/maps/de_dust2.bsp','cstrike/liblist.gam')) { if (!(Test-Path -LiteralPath (Join-Path $Dir $file) -PathType Leaf)) { return $false } }
    return $true
}
function Initialize-Juego {
    $juego = Join-Path $script:Raiz 'build/juego'
    if (Test-Juego $juego) { Mensaje OK 'Archivos del juego presentes'; return }
    $descarga = Join-Path $script:Raiz 'build/descarga'
    if (!(Test-Juego $descarga)) {
        Mensaje INFO 'Descargando juego con SteamCMD (~600 MB).'
        Invoke-Compose @('--profile','descarga','build','steamcmd')
        for ($i = 1; $i -le 4; $i++) {
            try { Invoke-Compose @('--profile','descarga','run','--rm','--no-deps','steamcmd','+force_install_dir','/descarga','+login','anonymous','+app_set_config','90','mod','cstrike','+app_update','90','validate','+quit') } catch { Mensaje AVISO "SteamCMD intento $i fallo; verifico archivos." }
            if (Test-Juego $descarga) { break }
        }
    }
    if (!(Test-Juego $descarga)) { throw 'SteamCMD no completo la descarga. Reintenta o copia valve y cstrike de Steam a build/juego.' }
    # Copia y preparacion dentro del contenedor Linux: no mueve/elimina directorios Windows.
    Invoke-Compose @('run','--rm','--no-deps','studio','python','/host-windows/preparar-juego.py')
    if (!(Test-Juego $juego)) { throw 'La preparacion del juego no termino.' }
}
function Show-Red($Red, [string]$Publica, [string]$WAN = '') {
    Mensaje OK "IP LAN: $($Red.LAN) | Gateway: $($Red.Gateway) | Adaptador: $($Red.Adaptador)"
    Mensaje INFO "MAC: $($Red.MAC) | DHCP: $($Red.DHCP). Reserva esta MAC/IP en DHCP del router; no cambio la IP de Windows."
    Mensaje INFO "IP publica HTTP: $Publica"
    Mensaje INFO "CGNAT: $(Get-Cgnat $Red.LAN $Publica $WAN)"
    Write-Host 'Si hay CGNAT/doble NAT, el forwarding normal puede fallar. Solicita IPv4 publica al ISP (fija opcional), reenvia tambien en el router superior o usa relay/VPS compatible con UDP. Cloudflare Tunnel comun no transporta este WebRTC UDP.'
    Write-Host "`nROUTER: configurar manualmente (no se puede confirmar desde esta PC):"
    foreach ($p in Get-Reglas) { Write-Host ("{0,-3} {1,-5} -> {2}:{1}" -f $p.Protocol,$p.Port,$Red.LAN) }
    Write-Host 'UDP 443 es HTTP/3 opcional; TCP 80/443 y UDP 27018 son necesarios para este despliegue. No abrir 27015, 27025, 27016, 27080 ni Docker API.'
}
function Get-LocalStatus { return Invoke-RestMethod -Uri 'http://127.0.0.1:27016/api/salas' -TimeoutSec 8 }
function Test-Dns([string]$Dominio, [string]$Publica) {
    try {
        $dns = @(Resolve-DnsName -Name $Dominio -Type A -DnsOnly | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
        if ($Publica -in $dns) { Mensaje OK "DNS A: $Dominio -> $Publica" }
        else { Mensaje AVISO "DNS A ($($dns -join ', ')) no apunta a $Publica. Crea/actualiza registro A de $Dominio, sin proxy/CDN." }
    } catch { Mensaje AVISO "DNS de $Dominio pendiente: $($_.Exception.Message)" }
}
function Wait-Salas {
    $deadline = (Get-Date).AddSeconds(300)
    do {
        try {
            $status = Get-LocalStatus
            if (@($status.salas).Count -gt 0 -and @($status.salas | Where-Object { !$_.online }).Count -eq 0) { Mensaje OK 'Web y todas las salas CS responden'; return }
        } catch { }
        Mensaje INFO 'Esperando web/salas (hasta 5 minutos)...'
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    Invoke-Compose @('logs','--tail','30','servidor','web')
    throw 'Web o salas no respondieron a tiempo. Revisa los logs anteriores.'
}
function Test-Https([string]$Dominio) {
    $ErrorActionPreference = 'Continue'
    # SNI/Host correctos, conexion directa a localhost. No depende del hairpin del router.
    if (!(Get-Command curl.exe -ErrorAction SilentlyContinue)) { Mensaje AVISO 'Falta curl.exe para comprobar HTTPS local con SNI.'; return $false }
    $result = & curl.exe --silent --show-error --fail --noproxy '*' --connect-timeout 5 --max-time 12 --resolve "${Dominio}:443:127.0.0.1" "https://$Dominio/api/status" 2>&1
    if ($LASTEXITCODE -eq 0) { Mensaje OK 'HTTPS local con certificado valido (no verifica Internet)'; return $true }
    Mensaje AVISO "HTTPS local pendiente: $($result -join ' '). Revisa DNS, forwarding TCP 80/443 y logs de Caddy."
    return $false
}
function Set-InicioAutomatico([switch]$Eliminar) {
    Assert-Admin
    $taskName = 'SLA-CS16 Public Host'
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing -and $existing.Description -ne "SLA-CS16 | $script:Raiz") { throw 'Existe una tarea del mismo nombre para otra instalacion; no la reemplazo.' }
    if ($Eliminar) { if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }; Mensaje OK 'Inicio automatico eliminado'; return }
    $exe = (Get-Process -Id $PID).Path
    $scriptPath = Join-Path $script:Raiz 'host-publico.ps1'
    $action = New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptPath`" -SoloIniciar" -WorkingDirectory $script:Raiz
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "SLA-CS16 | $script:Raiz" -Force | Out-Null
    Mensaje OK 'Tarea instalada al iniciar SESION con este usuario. Docker Desktop necesita sesion interactiva; no ejecuta antes del login.'
}
