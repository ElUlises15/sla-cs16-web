#Requires -Version 5.1
[CmdletBinding()]
param([switch]$EliminarFirewall)
. "$PSScriptRoot/host-windows/comun.ps1"
try {
    Assert-Windows
    Ensure-Docker
    Invoke-Compose @('stop','caddy','servidor','web','studio')
    if ($EliminarFirewall) { Set-Firewall -Eliminar }
    Mensaje OK 'Host detenido. No se eliminaron contenedores, volumenes ni archivos. La tarea opcional seguira iniciandolo al proximo login.'
} catch { Mensaje ERROR $_.Exception.Message; exit 1 }
