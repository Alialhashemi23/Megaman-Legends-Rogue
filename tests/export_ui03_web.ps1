# Test-only Workshop Web export and Workshop purchase check. Uses a local
# relay, controlled account replies and fresh browser profiles; never the live stack.
[CmdletBinding()]
param(
    [string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Godot_v4.7.1-stable_win64_console.exe'),
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$ui03Root = Split-Path -Parent $PSScriptRoot
$ui03ProjectPath = Join-Path $ui03Root 'project.godot'
$ui03PresetPath = Join-Path $ui03Root 'export_presets.cfg'
$ui03ProjectBytes = [IO.File]::ReadAllBytes($ui03ProjectPath)
$ui03PresetBytes = [IO.File]::ReadAllBytes($ui03PresetPath)
$ui03Project = [Text.Encoding]::UTF8.GetString($ui03ProjectBytes)
$ui03Presets = [Text.Encoding]::UTF8.GetString($ui03PresetBytes)
if (-not $ui03Project.Contains('run/main_scene="res://main.tscn"') -or -not $ui03Presets.Contains('tests/*,')) {
    throw 'Expected the ordinary main scene and production test exclusions.'
}
$ui03Web = Join-Path $ui03Root 'build/ui03-web'
New-Item -ItemType Directory -Force -Path $ui03Web | Out-Null
try {
    [IO.File]::WriteAllText($ui03ProjectPath, $ui03Project.Replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://tests/purchase_review_browser.tscn"'))
    [IO.File]::WriteAllText($ui03PresetPath, $ui03Presets.Replace('tests/*,', ''))
    & $Godot --headless --path $ui03Root --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture import failed.' }
    & $Godot --headless --path $ui03Root --export-release Web (Join-Path $ui03Web 'index.html')
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture export failed.' }
} finally {
    [IO.File]::WriteAllBytes($ui03ProjectPath, $ui03ProjectBytes)
    [IO.File]::WriteAllBytes($ui03PresetPath, $ui03PresetBytes)
}
Copy-Item -LiteralPath (Join-Path $ui03Root 'assets/fonts') -Destination $ui03Web -Recurse -Force
Copy-Item -LiteralPath (Join-Path $ui03Root 'assets/ui/volnutt_portrait.png') -Destination (Join-Path $ui03Web 'volnutt-portrait.png')
Copy-Item -LiteralPath (Join-Path $ui03Root 'assets/ui/icon.png') -Destination (Join-Path $ui03Web 'volnutt-icon.png')
if (-not $ExportOnly) {
    & node (Join-Path $ui03Root 'tests/purchase_review_web.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'UI-03 browser verification failed.' }
}
