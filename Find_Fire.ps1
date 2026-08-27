# Find-Fire.ps1
#
# Launcher for the NIFC Wildfire Tool.

$ErrorActionPreference = "Stop"

$mainScript = Join-Path `
    $PSScriptRoot `
    "Bin\WildfireTool.ps1"

if (-not (Test-Path $mainScript)) {

    Write-Error "Could not find the main application script:"
    Write-Error $mainScript

    exit 1
}

& $mainScript