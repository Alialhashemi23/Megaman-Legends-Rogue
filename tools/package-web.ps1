# Export the browser build and package it as build/RelicDiver-Web.zip, the
# bundle the online server (server/, Dockerfile) serves. Needs the Web export
# templates for Godot 4.7.1 (Editor > Manage Export Templates).
[CmdletBinding()]
param([string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Godot_v4.7.1-stable_win64_console.exe'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $projectRoot 'build'
$webPath = Join-Path $buildPath 'web'
$archivePath = Join-Path $buildPath 'RelicDiver-Web.zip'
if (Test-Path -LiteralPath $webPath) { Remove-Item -LiteralPath $webPath -Recurse -Force }
New-Item -ItemType Directory -Path $webPath | Out-Null
& $Godot --headless --path $projectRoot --export-release Web (Join-Path $webPath 'index.html')
if ($LASTEXITCODE -ne 0) { throw 'Web export failed. Are the Web export templates installed?' }
foreach ($name in @('LICENSE.md', 'GODOT-LICENSE.txt', 'CHARACTER-CREDITS.md', 'AUDIO-NOTES.md')) {
    Copy-Item -LiteralPath (Join-Path $buildPath $name) -Destination $webPath
}
foreach ($folder in @('font-licenses', 'audio-licenses')) {
    Copy-Item -LiteralPath (Join-Path $buildPath $folder) -Destination $webPath -Recurse
}
# The loading screen (web/shell.html) uses the game's fonts before the game has loaded.
$fontPath = Join-Path $webPath 'fonts'
New-Item -ItemType Directory -Path $fontPath | Out-Null
foreach ($name in @('RussoOne-Regular.ttf', 'BarlowSemiCondensed-SemiBold.ttf')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot "assets/fonts/$name") -Destination $fontPath
}
$partialPath = "$archivePath.partial"
if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Entry names need forward slashes: the server image unpacks this on Linux.
$archive = [System.IO.Compression.ZipFile]::Open($partialPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in Get-ChildItem -LiteralPath $webPath -File -Recurse) {
        $name = $file.FullName.Substring($webPath.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }
if ((Get-Item -LiteralPath $partialPath).Length -ge 100MB) { throw 'The web ZIP exceeds GitHub normal Git file limits.' }
Move-Item -LiteralPath $partialPath -Destination $archivePath -Force
Get-Item -LiteralPath $archivePath | Select-Object Name, Length
