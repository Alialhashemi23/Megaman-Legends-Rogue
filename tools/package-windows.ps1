# Package the existing tested Windows build, excluding saves and recordings.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildPath = Join-Path $projectRoot 'build'
$archivePath = Join-Path $buildPath 'RelicDiver-Windows.zip'
$partialPath = "$archivePath.partial"
$required = @('RelicDiver.exe', 'RelicDiver_console.exe', 'RelicDiver.pck',
    'README.md', 'CHANGELOG.md', 'LICENSE.md', 'GODOT-LICENSE.txt',
    'CHARACTER-CREDITS.md', 'AUDIO-NOTES.md')
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $buildPath $name))) {
        throw "Missing build file: $name"
    }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($partialPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $required) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,
            (Join-Path $buildPath $name), $name, [System.IO.Compression.CompressionLevel]::Optimal)
    }
    foreach ($folder in @('font-licenses', 'audio-licenses')) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $buildPath $folder) -File -Recurse) {
            $name = $file.FullName.Substring($buildPath.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,
                $file.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
} finally {
    $archive.Dispose()
}
if ((Get-Item -LiteralPath $partialPath).Length -ge 100MB) {
    throw 'The portable ZIP exceeds GitHub normal Git file limits. Keep the existing published bundle and review packaging.'
}
Move-Item -LiteralPath $partialPath -Destination $archivePath -Force
Get-Item -LiteralPath $archivePath | Select-Object Name, Length
