#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][uri]$URL)
$ErrorActionPreference = 'Stop'
try {
    if ($URL.Scheme -ne 'https' -or $URL.Port -ne 443 -or $URL.UserInfo) { throw 'Usa https://dominio sin credenciales, puerto alternativo ni rutas.' }
    $base = $URL.GetLeftPart([UriPartial]::Authority)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host 'Ejecutar desde una PC en OTRA conexion. Desde el host solo prueba hairpin/local.'
    $status = Invoke-RestMethod "$base/api/status" -TimeoutSec 15
    Write-Host '[OK] HTTPS con certificado valido y web respondiendo'
    $status | ConvertTo-Json -Depth 6 | Write-Host
    Write-Host "WebRTC/UDP real: abre $base/diagnostico.html y pulsa Probar. HTTPS solo no prueba el juego."
} catch { Write-Error "Fallo externo: $($_.Exception.Message)"; exit 1 }
