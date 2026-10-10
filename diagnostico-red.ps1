#Requires -Version 5.1
[CmdletBinding()]
param([string]$IPLan = '', [string]$WanRouter = '')
. "$PSScriptRoot/host-windows/comun.ps1"
try {
    Assert-Windows
    $red = Get-Red $IPLan
    $publica = ''; try { $publica = Get-PublicIP } catch { Mensaje AVISO $_.Exception.Message }
    Show-Red $red $publica $WanRouter
    $e = Read-Env
    if ($e['DOMINIO']) {
        try {
            $dns = @(Resolve-DnsName -Name $e['DOMINIO'] -Type A -DnsOnly | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress)
            Mensaje INFO "DNS A: $($dns -join ', ')"
            if ($publica -and $publica -notin $dns) { Mensaje AVISO 'DNS A no apunta a la IP publica detectada. Desactiva proxy/CDN para WebRTC directo.' }
        } catch { Mensaje AVISO "DNS no resuelve: $($_.Exception.Message)" }
        $null = Test-Https $e['DOMINIO']
    } else { Mensaje AVISO 'No hay dominio configurado. Ejecuta host-publico.ps1.' }
    foreach ($port in 80,443,27016,27080) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1',$port)
            if (!$task.Wait(3000)) { throw 'timeout' }
            Mensaje OK "TCP $port local acepta conexiones"
        } catch { Mensaje AVISO "TCP $port local no responde" }
        finally { $client.Dispose() }
    }
    try {
        Ensure-Docker
        Assert-Publicaciones
        Get-Publicaciones | Format-Table -AutoSize
        Mensaje INFO 'UDP 27018: publicacion Compose comprobada; el socket ICE se crea al conectar un navegador. No es una prueba UDP externa.'
    } catch { Mensaje AVISO $_.Exception.Message }
    Get-NetFirewallRule -Group 'SLA-CS16 Public Host' -ErrorAction SilentlyContinue | Select-Object DisplayName,Enabled,Action,Profile | Format-Table
    Write-Host "`nDesde OTRA red abre $($e['URL_JUEGO'])/diagnostico.html y ejecuta:"
    Write-Host ".\host-windows\verificar-externo.ps1 -URL $($e['URL_JUEGO'])"
    Mensaje AVISO 'No puedo verificar UDP 27018 desde Internet desde esta PC. Causas posibles: forwarding, firewall Windows/router, doble NAT, CGNAT, ISP, VPN o falta de NAT loopback para clientes locales.'
} catch { Mensaje ERROR $_.Exception.Message; exit 1 }
