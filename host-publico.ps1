#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Dominio = '',
    [string]$IPLan = '',
    [string]$IPPublica = '',
    [string]$WanRouter = '',
    [switch]$ConfigurarFirewall,
    [switch]$EliminarFirewall,
    [switch]$InstalarInicioAutomatico,
    [switch]$EliminarInicioAutomatico,
    [switch]$SoloIniciar
)
. "$PSScriptRoot/host-windows/comun.ps1"
try {
    Assert-Windows
    if ($ConfigurarFirewall -and $EliminarFirewall) { throw 'No combines ConfigurarFirewall y EliminarFirewall.' }
    if ($InstalarInicioAutomatico -and $EliminarInicioAutomatico) { throw 'No combines instalar y eliminar inicio automatico.' }
    if ($Dominio -and !(Test-Dominio $Dominio)) { throw 'Dominio invalido: usa cs.ejemplo.com sin esquema ni puerto.' }
    if ($WanRouter -and !(Test-IPv4 $WanRouter)) { throw 'WanRouter invalida.' }
    if ($IPPublica -and (Get-RangoIPv4 $IPPublica) -ne 'Publica') { throw 'IPPublica debe ser IPv4 publica enrutable.' }
    if ($IPLan -and !(Test-IPv4 $IPLan)) { throw 'IPLan invalida.' }
    if ($EliminarInicioAutomatico) { Set-InicioAutomatico -Eliminar }
    if ($EliminarFirewall) { Set-Firewall -Eliminar }
    if ($EliminarInicioAutomatico -or $EliminarFirewall) { return }
    if ($ConfigurarFirewall -or $InstalarInicioAutomatico) { Assert-Admin }
    Write-Host "`nSLA CS 1.6 - servidor publico Windows`n"
    Ensure-Docker
    $red = Get-Red $IPLan
    $actual = Read-Env
    if (!$IPPublica) { $IPPublica = Get-PublicIP }
    $changes = Get-OnlineEnv $actual $IPPublica $Dominio
    Write-Env $changes
    Initialize-Archivos
    Show-Red $red $IPPublica $WanRouter
    Test-Dns $changes['DOMINIO'] $IPPublica
    Assert-Publicaciones
    Test-PuertosLibres
    if ($ConfigurarFirewall) { Set-Firewall }
    else { Mensaje INFO 'Firewall: usa -ConfigurarFirewall desde PowerShell como administrador para crear/verificar reglas.' }
    if ($SoloIniciar) {
        if (!(Test-Juego (Join-Path $script:Raiz 'build/juego'))) { throw 'Completa primero .\host-publico.ps1 sin SoloIniciar.' }
    } else {
        Mensaje INFO 'Construyendo imagenes (Docker usa cache).'
        Invoke-Compose @('build','servidor','web','studio')
        Initialize-Juego
        Invoke-Compose @('run','--rm','--no-deps','studio','python','-m','app.cli','build')
    }
    Invoke-Compose @('run','--rm','--no-deps','caddy','caddy','validate','--config','/etc/caddy/Caddyfile','--adapter','caddyfile')
    Invoke-Compose @('up','-d','servidor','web','studio','caddy')
    # servidor comparte el namespace de web: recrearlo evita referencias a una web vieja.
    Invoke-Compose @('up','-d','--no-deps','--force-recreate','servidor','studio')
    Wait-Salas
    $e = Read-Env
    $https = Test-Https $e['DOMINIO']
    if (!$https) { Invoke-Compose @('logs','--tail','25','caddy') }
    if ($InstalarInicioAutomatico) { Set-InicioAutomatico }
    Mensaje OK 'Servicios levantados. Datos y configuracion conservados.'
    Write-Host "`nURL publica configurada: $($e['URL_JUEGO'])"
    Write-Host "DNS A: $($e['DOMINIO']) -> $IPPublica (sslip.io lo resuelve automaticamente)."
    Write-Host 'Studio local: http://localhost:27080'
    Write-Host "Prueba desde otra red: $($e['URL_JUEGO'])/diagnostico.html"
    Mensaje AVISO 'Accesibilidad desde Internet/UDP aun NO verificada. Completa router/DNS y prueba con datos moviles u otra red.'
} catch { Mensaje ERROR $_.Exception.Message; exit 1 }
