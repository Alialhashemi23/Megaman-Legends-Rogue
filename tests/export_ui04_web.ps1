# Test-only handheld layout export. Uses a local relay, synthetic lobby
# and fresh browser profiles; never the live account stack.
[CmdletBinding()]
param(
    [string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Godot_v4.7.1-stable_win64_console.exe'),
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$ui04Root = Split-Path -Parent $PSScriptRoot
$ui04ProjectPath = Join-Path $ui04Root 'project.godot'
$ui04PresetPath = Join-Path $ui04Root 'export_presets.cfg'
$ui04ProjectBytes = [IO.File]::ReadAllBytes($ui04ProjectPath)
$ui04PresetBytes = [IO.File]::ReadAllBytes($ui04PresetPath)
$ui04Project = [Text.Encoding]::UTF8.GetString($ui04ProjectBytes)
$ui04Presets = [Text.Encoding]::UTF8.GetString($ui04PresetBytes)
if (-not $ui04Project.Contains('run/main_scene="res://main.tscn"') -or -not $ui04Presets.Contains('tests/*,')) {
    throw 'Expected the ordinary main scene and production test exclusions.'
}
$ui04Web = Join-Path $ui04Root 'build/ui04-web'
New-Item -ItemType Directory -Force -Path $ui04Web | Out-Null
try {
    [IO.File]::WriteAllText($ui04ProjectPath, $ui04Project.Replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://tests/handheld_browser.tscn"'))
    [IO.File]::WriteAllText($ui04PresetPath, $ui04Presets.Replace('tests/*,', ''))
    & $Godot --headless --path $ui04Root --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture import failed.' }
    & $Godot --headless --path $ui04Root --export-release Web (Join-Path $ui04Web 'index.html')
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture export failed.' }
} finally {
    [IO.File]::WriteAllBytes($ui04ProjectPath, $ui04ProjectBytes)
    [IO.File]::WriteAllBytes($ui04PresetPath, $ui04PresetBytes)
}
Copy-Item -LiteralPath (Join-Path $ui04Root 'assets/fonts') -Destination $ui04Web -Recurse -Force
Copy-Item -LiteralPath (Join-Path $ui04Root 'assets/ui/volnutt_portrait.png') -Destination (Join-Path $ui04Web 'volnutt-portrait.png')
Copy-Item -LiteralPath (Join-Path $ui04Root 'assets/ui/icon.png') -Destination (Join-Path $ui04Web 'volnutt-icon.png')
if (-not $ExportOnly) {
    & node (Join-Path $ui04Root 'tests/handheld_web.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'UI-04 browser verification failed.' }
}

