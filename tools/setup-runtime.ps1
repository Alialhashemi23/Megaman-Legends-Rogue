# Prepare a fresh Windows clone using the committed portable bundle.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $PSScriptRoot 'Godot_v4.7.1-stable_win64.exe'
if (Test-Path -LiteralPath $enginePath) {
    Write-Host 'Godot runtime is already available.'
    exit 0
}
$archivePath = Join-Path $projectRoot 'build/RelicDiver-Windows.zip'
$buildPath = Join-Path $projectRoot 'build'
if (-not (Test-Path -LiteralPath $archivePath)) {
    throw 'Missing build/RelicDiver-Windows.zip. Get the complete repository or install Godot 4.7.1 and open project.godot.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $buildPath -Force
Copy-Item -LiteralPath (Join-Path $buildPath 'RelicDiver.exe') -Destination $enginePath
Copy-Item -LiteralPath (Join-Path $buildPath 'RelicDiver_console.exe') -Destination (Join-Path $PSScriptRoot 'Godot_v4.7.1-stable_win64_console.exe')
Write-Host 'Godot 4.7.1 is ready. Use Play.cmd or Edit.cmd.'
