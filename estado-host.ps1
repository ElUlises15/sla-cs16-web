#Requires -Version 5.1
[CmdletBinding()]
param([string]$IPLan = '', [string]$WanRouter = '')
. "$PSScriptRoot/host-windows/comun.ps1"
try {
    Assert-Windows
    $e = Read-Env
    $red = Get-Red $IPLan
    $publica = ''; try { $publica = Get-PublicIP } catch { Mensaje AVISO $_.Exception.Message }
    Show-Red $red $publica $WanRouter
    Write-Host "Dominio: $($e['DOMINIO']) | URL configurada: $($e['URL_JUEGO']) | IP anunciada por bridge: $($e['IP_PUBLICA'])"
    if ($publica -and $publica -ne $e['IP_PUBLICA']) { Mensaje AVISO 'Cambio la IP publica. Ejecuta host-publico.ps1 y actualiza DNS si corresponde.' }
    Ensure-Docker
    Invoke-Compose @('ps','-a')
    Get-Publicaciones | Format-Table -AutoSize
    try { Get-LocalStatus | ConvertTo-Json -Depth 8 | Write-Host } catch { Mensaje AVISO "Web local no responde: $($_.Exception.Message)" }
    if ($e['DOMINIO']) { $null = Test-Https $e['DOMINIO'] }
    Get-NetFirewallRule -Group 'SLA-CS16 Public Host' -ErrorAction SilentlyContinue | Select-Object DisplayName,Enabled,Action,Profile | Format-Table
    Invoke-Compose @('logs','--tail','15','caddy','web','servidor')
    Mensaje INFO 'UDP publicado no equivale a UDP accesible desde Internet. Ejecuta diagnostico-red.ps1.'
} catch { Mensaje ERROR $_.Exception.Message; exit 1 }
