# Test-only overlay Web export and real-account co-op check. Uses a disposable
# PostgreSQL container, API/relay and browser profiles; never the live stack.
[CmdletBinding()]
param(
    [string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Godot_v4.7.1-stable_win64_console.exe'),
    [switch]$ExportOnly
)
$ErrorActionPreference = 'Stop'
$ui02Root = Split-Path -Parent $PSScriptRoot
$ui02ProjectPath = Join-Path $ui02Root 'project.godot'
$ui02PresetPath = Join-Path $ui02Root 'export_presets.cfg'
$ui02ProjectBytes = [IO.File]::ReadAllBytes($ui02ProjectPath)
$ui02PresetBytes = [IO.File]::ReadAllBytes($ui02PresetPath)
$ui02Project = [Text.Encoding]::UTF8.GetString($ui02ProjectBytes)
$ui02Presets = [Text.Encoding]::UTF8.GetString($ui02PresetBytes)
if (-not $ui02Project.Contains('run/main_scene="res://main.tscn"') -or -not $ui02Presets.Contains('tests/*,')) {
    throw 'Expected the ordinary main scene and production test exclusions.'
}
$ui02Web = Join-Path $ui02Root 'build/ui02-web'
New-Item -ItemType Directory -Force -Path $ui02Web | Out-Null
try {
    [IO.File]::WriteAllText($ui02ProjectPath, $ui02Project.Replace('run/main_scene="res://main.tscn"', 'run/main_scene="res://tests/ui02_browser_driver.tscn"'))
    [IO.File]::WriteAllText($ui02PresetPath, $ui02Presets.Replace('tests/*,', ''))
    & $Godot --headless --path $ui02Root --editor --import
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture import failed.' }
    & $Godot --headless --path $ui02Root --export-release Web (Join-Path $ui02Web 'index.html')
    if ($LASTEXITCODE -ne 0) { throw 'Test fixture export failed.' }
} finally {
    [IO.File]::WriteAllBytes($ui02ProjectPath, $ui02ProjectBytes)
    [IO.File]::WriteAllBytes($ui02PresetPath, $ui02PresetBytes)
}
Copy-Item -LiteralPath (Join-Path $ui02Root 'assets/fonts') -Destination $ui02Web -Recurse -Force
Copy-Item -LiteralPath (Join-Path $ui02Root 'assets/ui/volnutt_portrait.png') -Destination (Join-Path $ui02Web 'volnutt-portrait.png')
Copy-Item -LiteralPath (Join-Path $ui02Root 'assets/ui/icon.png') -Destination (Join-Path $ui02Web 'volnutt-icon.png')
if (-not $ExportOnly) {
    & node (Join-Path $ui02Root 'tests/ui02_web_e2e.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'UI-02 browser/account verification failed.' }
}
