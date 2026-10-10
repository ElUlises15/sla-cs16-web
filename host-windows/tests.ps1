#Requires -Version 5.1
# Sin Pester ni instalaciones adicionales. Solo temporales; no Docker/firewall/router.
[CmdletBinding()]
param([string]$ComposeExe = '')
. "$PSScriptRoot/comun.ps1"
$script:Total = 0
function Assert($Condition, [string]$Name) { if (!$Condition) { throw "FALLO: $Name" }; $script:Total++; Write-Host "[OK] $Name" }
function Throws([scriptblock]$Action, [string]$Name) { $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }; Assert $failed $Name }
$temp = Join-Path ([IO.Path]::GetTempPath()) ("sla-host-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $desktopPaths = @(Get-DockerDesktopRutas)
    Assert ($desktopPaths.Count -eq 2 -and $desktopPaths[0] -like '*Docker\Docker' -and $desktopPaths[1] -like '*Programs\DockerDesktop') 'Docker Desktop rutas global y por usuario'
    foreach ($ip in '1.2.3.4','255.255.255.255','0.0.0.0','181.23.45.67') { Assert (Test-IPv4 $ip) "IPv4 valida $ip" }
    foreach ($ip in '256.1.1.1','1.2.3','1.2.3.4.5','01.2.3.4','::1','1.2.3.-1','1.2.3.4 extra','') { Assert (!(Test-IPv4 $ip)) "IPv4 invalida $ip" }
    Assert ((Get-Sslip '181.23.45.67') -eq '181-23-45-67.sslip.io') 'conversion sslip'
    Throws { Get-Sslip '192.168.1.1' } 'sslip rechaza privada'
    foreach ($ip in '10.0.0.1','172.16.0.0','172.31.255.255','192.168.1.50') { Assert ((Get-RangoIPv4 $ip) -eq 'Privada') "RFC1918 $ip" }
    foreach ($ip in '100.64.0.0','100.127.255.255') { Assert ((Get-RangoIPv4 $ip) -eq 'CGNAT') "CGNAT $ip" }
    foreach ($ip in '100.63.255.255','100.128.0.0','172.15.255.255','172.32.0.0','181.23.45.67') { Assert ((Get-RangoIPv4 $ip) -eq 'Publica') "Limite publico $ip" }
    foreach ($ip in '0.0.0.0','224.0.0.1','203.0.113.2') { Assert ((Get-RangoIPv4 $ip) -eq 'Reservada') "Reservada $ip" }
    Assert ((Get-Cgnat '192.168.1.50' '181.23.45.67') -like 'Indeterminado*') 'LAN privada no prueba CGNAT'
    Assert ((Get-Cgnat '192.168.1.50' '181.23.45.67' '100.64.1.1') -like 'Probable CGNAT*') 'WAN compartida'
    Assert ((Get-Cgnat '192.168.1.50' '181.23.45.67' '192.168.0.2') -like 'Probable doble NAT*') 'doble NAT'
    Assert ((Get-Cgnat '192.168.1.50' '181.23.45.67' '181.23.45.67') -like 'No detectado*') 'WAN coincide'
    Assert ((Get-Cgnat '192.168.1.50' '181.23.45.67' '8.8.8.8') -like 'Posible NAT*') 'WAN difiere'
    foreach ($domain in 'cs.slatv.live','181-23-45-67.sslip.io') { Assert (Test-Dominio $domain) "Dominio $domain" }
    foreach ($domain in 'https://cs.slatv.live','localhost','foo, bar.com','foo.com/path','foo.com:443','-foo.com','1.2.3.4','foo.com`n') { Assert (!(Test-Dominio $domain)) "Dominio rechazado $domain" }
    $rules = @(Get-Reglas)
    Assert ($rules.Count -eq 4 -and @($rules.Name | Select-Object -Unique).Count -eq 4) 'cuatro reglas unicas'
    Assert (($rules | ForEach-Object { "$($_.Protocol)/$($_.Port)" }) -join ',' -eq 'TCP/80,TCP/443,UDP/443,UDP/27018') 'solo puertos previstos'
    $envFile = Join-Path $temp '.env'
    [IO.File]::WriteAllText($envFile, "# mi config`nCONTRASENA='grupo privado'`nOTRA=conservar`nRCON_PASSWORD=secreto`nARCHIVOS=servidor`nDOMINIO=cs.slatv.live`n")
    $original = Read-Env $envFile
    $c = Get-OnlineEnv $original '181.23.45.67'
    Write-Env $c $envFile
    $updated = Read-Env $envFile
    Assert ($updated['RCON_PASSWORD'] -eq 'secreto' -and $updated['OTRA'] -eq 'conservar') 'env preserva configuracion/secretos'
    Assert ($updated['ARCHIVOS'] -eq 'servidor' -and $updated['CONTRASENA'] -eq 'grupo privado') 'modo privado existente preservado'
    Assert ($updated['DOMINIO_CADDY'] -eq 'cs.slatv.live' -and $updated['BIND_WEB'] -eq '127.0.0.1' -and $updated['CONFIAR_PROXY'] -eq '1') 'online y proxy'
    $before = [IO.File]::ReadAllText($envFile)
    Write-Env (Get-OnlineEnv $updated '181.23.45.67') $envFile
    Assert ([IO.File]::ReadAllText($envFile) -eq $before) 'env idempotente'
    Assert ([IO.File]::ReadAllText($envFile).StartsWith('# mi config')) 'env conserva comentarios'
    Assert ([IO.File]::ReadAllBytes($envFile)[0] -ne 239) 'env sin BOM'
    $public = Get-OnlineEnv @{ ARCHIVOS='servidor' } '181.23.45.67'
    Assert ($public['ARCHIVOS'] -eq 'propios' -and $public['RCON_PASSWORD'].Length -eq 48) 'pasar local a publico seguro'
    Assert ((Get-OnlineEnv @{ DOMINIO='1-2-3-4.sslip.io' } '181.23.45.67')['DOMINIO'] -eq '181-23-45-67.sslip.io') 'actualiza sslip con IP dinamica'
    Throws { Get-OnlineEnv @{ MAX_POR_IP='0' } '181.23.45.67' } 'limite IP obligatorio'
    Throws { Write-Env @{ OTRA="mal`nTOKEN=falso" } $envFile } 'rechaza inyeccion env'
    Write-Env @{ VALOR="hola' mundo `$dinero" } $envFile
    Assert ((Read-Env $envFile)['VALOR'] -eq "hola' mundo `$dinero") 'comillas y dolar literal'
    $rows = Convert-DockerPs "{`"Service`":`"web`",`"State`":`"running`",`"Publishers`":[]}`n{`"Service`":`"servidor`",`"State`":`"exited`",`"Publishers`":[]}"
    Assert (@($rows).Count -eq 2 -and $rows[0].Service -eq 'web') 'Docker JSON por linea'
    Assert (@(Convert-DockerPs '[{"Service":"web","State":"running","Publishers":[]}]').Count -eq 1) 'Docker JSON array'
    Assert (@(Convert-DockerPs '').Count -eq 0) 'Docker JSON vacio'
    Throws { Convert-DockerPs 'error daemon' } 'Docker JSON invalido'
    # Funcion docker simulada: validar los argumentos reales enviados por wrappers.
    function docker {
        $script:UltimosDocker = @($args)
        $global:LASTEXITCODE = 0
        if ('ps' -in $args) { return '[{"Service":"web","State":"running","Publishers":[{"Protocol":"udp","PublishedPort":27018}]}]' }
        'ok'
    }
    $null = Invoke-Compose @('up','-d','web') -Capturar
    Assert ($script:UltimosDocker[0] -eq 'compose' -and $script:UltimosDocker[-1] -eq 'web' -and '--env-file' -in $script:UltimosDocker) 'wrapper conserva argumentos Compose/rutas'
    # Seleccion de interfaz por ruta/metrica, o por IP explicita; gateway/MAC/DHCP.
    function Get-NetRoute { param($AddressFamily,$DestinationPrefix); @([pscustomobject]@{InterfaceIndex=1;NextHop='192.168.1.1';RouteMetric=10},[pscustomobject]@{InterfaceIndex=2;NextHop='10.0.0.1';RouteMetric=2}) }
    function Get-NetIPInterface { param($AddressFamily,$InterfaceIndex); [pscustomobject]@{Dhcp='Enabled';InterfaceAlias="NIC-$InterfaceIndex";InterfaceMetric=5} }
    function Get-NetAdapter { @([pscustomobject]@{ifIndex=1;MacAddress='AA-BB-CC-DD-EE-01'},[pscustomobject]@{ifIndex=2;MacAddress='AA-BB-CC-DD-EE-02'}) }
    function Get-NetIPAddress { param($AddressFamily,$InterfaceIndex); [pscustomobject]@{IPAddress=$(if($InterfaceIndex -eq 1){'192.168.1.50'}else{'10.0.0.2'});AddressState='Preferred';SkipAsSource=$false} }
    $network = Get-Red
    Assert ($network.LAN -eq '10.0.0.2' -and $network.Gateway -eq '10.0.0.1') 'red elige menor metrica mock'
    $network = Get-Red '192.168.1.50'
    Assert ($network.MAC -eq 'AA-BB-CC-DD-EE-01' -and $network.DHCP -eq 'Enabled') 'red override conserva MAC/DHCP mock'
    Throws { Get-Red '192.168.1.99' } 'rechaza IP LAN no asignada'
    # Puertos propios en segundo arranque: no intenta reservar el mux UDP del proyecto.
    function Get-Publicaciones { [pscustomobject]@{Servicio='web';IP='0.0.0.0';Puerto=27018;Destino=27018;Protocolo='udp'} }
    Test-PuertosLibres
    Assert $true 'segundo arranque reconoce publicacion propia mock'
    # Parsing del motor real, tambien en Windows PowerShell 5.1.
    foreach ($file in @(Get-ChildItem $script:Raiz -Filter '*.ps1') + @(Get-ChildItem $PSScriptRoot -Filter '*.ps1')) {
        $tokens=$null; $errors=$null
        $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert (!$errors) "PowerShell parse $($file.Name)"
        if ($file.Name -eq 'host-publico.ps1') {
            $params = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            foreach ($name in 'Dominio','IPLan','IPPublica','WanRouter','ConfigurarFirewall','EliminarFirewall','InstalarInicioAutomatico','EliminarInicioAutomatico','SoloIniciar') { Assert ($name -in $params) "Argumento $name" }
        }
    }
    # Mock cmdlets firewall: segunda ejecucion reutiliza reglas; borrar conserva ajenas.
    $script:MockRules = @{}; $script:Creates=0
    function Assert-Admin {}
    function Get-NetFirewallRule { param($Name); if ($script:MockRules.ContainsKey($Name)) { $script:MockRules[$Name] } }
    function New-NetFirewallRule { param($Name,$DisplayName,$Group,$Direction,$Action,$Protocol,$LocalPort,$Profile); $script:Creates++; $script:MockRules[$Name]=[pscustomobject]@{Name=$Name;Group=$Group} }
    function Set-NetFirewallRule { param([Parameter(ValueFromPipeline=$true)]$InputObject,$Enabled,$Direction,$Action,$Profile) }
    function Get-NetFirewallPortFilter { param([Parameter(ValueFromPipeline=$true)]$InputObject); process { $InputObject } }
    function Set-NetFirewallPortFilter { param([Parameter(ValueFromPipeline=$true)]$InputObject,$Protocol,$LocalPort) }
    function Remove-NetFirewallRule { param([Parameter(ValueFromPipeline=$true)]$InputObject); process { $script:MockRules.Remove($InputObject.Name) } }
    Set-Firewall; Set-Firewall
    Assert ($script:Creates -eq 4 -and $script:MockRules.Count -eq 4) 'firewall idempotente mock'
    $script:MockRules['AJENA']=[pscustomobject]@{Name='AJENA';Group='Otro'}
    Set-Firewall -Eliminar
    Assert ($script:MockRules.Count -eq 1 -and $script:MockRules.ContainsKey('AJENA')) 'borra solo reglas propias mock'
    $script:MockRules['SLA-CS16-TCP-80']=[pscustomobject]@{Name='SLA-CS16-TCP-80';Group='Otro'}
    Throws { Set-Firewall } 'no modifica regla ajena con nombre coincidente'
    if ($ComposeExe) {
        # Validar la union con el binario real de Compose sin daemon ni .env del usuario.
        $composeEnv = Join-Path $temp 'compose.env'
        Write-Env (Get-OnlineEnv @{} '181.23.45.67') $composeEnv
        $argsCompose = @('--project-directory',$script:Raiz,'--env-file',$composeEnv,'-f',"$script:Raiz/docker-compose.yml",'-f',"$script:Raiz/docker-compose.windows.yml",'--profile','online','config','--format','json')
        $json = & $ComposeExe @argsCompose
        Assert ($LASTEXITCODE -eq 0) 'Compose real valida override'
        $config = ConvertFrom-Json ($json -join "`n")
        Assert ($config.services.studio.ports[0].host_ip -eq '127.0.0.1') 'Studio loopback en Compose real'
        Assert ($config.services.web.ports.Count -eq 2 -and $config.services.web.ports[0].host_ip -eq '127.0.0.1') 'web interna en Compose real'
        Assert ($config.services.servidor.network_mode -eq 'service:web' -and !$config.services.servidor.PSObject.Properties['ports']) 'CS sin puertos publicados'
        Assert (@($config.services.caddy.ports).Count -eq 3) 'Caddy 80 TCP y 443 TCP/UDP'
        Assert ($config.services.caddy.volumes | Where-Object { $_.target -eq '/etc/caddy/Caddyfile' -and $_.source -like '*host-windows*Caddyfile' }) 'Caddy usa filtro privado Windows'
        # Compose Linux/VPS base sigue siendo valido y mantiene Caddy original.
        $baseJson = & $ComposeExe --project-directory $script:Raiz --env-file $composeEnv -f "$script:Raiz/docker-compose.yml" --profile online config --format json
        Assert ($LASTEXITCODE -eq 0) 'Compose base Linux/VPS valida'
        $baseConfig = ConvertFrom-Json ($baseJson -join "`n")
        Assert ($baseConfig.services.caddy.volumes | Where-Object { $_.target -eq '/etc/caddy/Caddyfile' -and $_.source -notlike '*host-windows*' }) 'Caddy base sin cambios'
    }
    Write-Host "PASARON $script:Total pruebas. Mocks no prueban Docker Desktop ni Internet."
} finally {
    # Unica eliminacion: temporal generado por esta prueba, comprobado antes.
    $resolved = [IO.Path]::GetFullPath($temp)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'sla-host-tests-*') { throw 'Temporal fuera del destino esperado.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
