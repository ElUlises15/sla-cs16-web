#Requires -Version 5.1
[CmdletBinding()]
param()
. "$PSScriptRoot/host-windows/comun.ps1"
try {
    Assert-Windows
    if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw 'Falta Git para Windows.' }
    $dirty = & git -C $script:Raiz status --porcelain
    if ($LASTEXITCODE -ne 0) { throw 'No es un repositorio Git.' }
    if ($dirty) { throw 'Hay cambios locales en archivos del repositorio. Guarda/commitea tus cambios antes de actualizar. .env, build y metricas no se borran.' }
    & git -C $script:Raiz pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull fallo; no reconstruyo. Revisa red o divergencia de ramas.' }
    & "$script:Raiz/host-publico.ps1"
    if ($LASTEXITCODE -ne 0) { throw 'Actualizacion/health checks fallo.' }
} catch { Mensaje ERROR $_.Exception.Message; exit 1 }
