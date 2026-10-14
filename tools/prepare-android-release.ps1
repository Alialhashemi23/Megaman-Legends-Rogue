# Stage verified immutable APK + metadata locally. Does not publish or deploy.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$Notes,
    [int]$MinimumOnlineVersionCode = 2,
    [string]$Output,
    [string]$Toolchain = 'D:\Android'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Output) { $Output = Join-Path $projectRoot 'build/android-release' }
$apkFile = Get-Item -LiteralPath $Apk
$jdk = Get-ChildItem -LiteralPath (Join-Path $Toolchain 'jdk') -Directory | Select-Object -First 1
$env:JAVA_HOME = $jdk.FullName
$buildTools = Join-Path $Toolchain 'sdk/build-tools/35.0.1'
$manifest = & (Join-Path $buildTools 'aapt.exe') dump badging $apkFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'Could not read APK manifest.' }
$packageLine = $manifest | Where-Object { $_ -match '^package:' } | Select-Object -First 1
if ($packageLine -notmatch "name='dev.galosengen.relicdiver' versionCode='([0-9]+)' versionName='([^']+)'") { throw 'Wrong app ID or invalid Android version.' }
$code = [int]$matches[1]; $versionName = $matches[2]
if ($MinimumOnlineVersionCode -lt 1 -or $MinimumOnlineVersionCode -gt $code) { throw 'Minimum online code must be between 1 and the APK versionCode.' }
if ($Notes.Length -gt 4000) { throw 'Release notes are limited to 4000 characters.' }
$cert = & (Join-Path $buildTools 'apksigner.bat') verify --print-certs $apkFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
$certificate = $cert | Where-Object { $_ -match '^Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]{64})$' } | Select-Object -First 1
if ($certificate -notmatch '^Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]{64})$') { throw 'Missing APK signing certificate fingerprint.' }
$fingerprint = $matches[1].ToLowerInvariant()
$net = [IO.File]::ReadAllText((Join-Path $projectRoot 'scripts/net.gd'))
if ($net -notmatch 'const NET_VERSION = ([0-9]+)') { throw 'Could not find game protocol.' }
$protocol = [int]$matches[1]
$hash = (Get-FileHash -LiteralPath $apkFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$destination = Join-Path $Output "relic-diver-$code.apk"
if (Test-Path -LiteralPath $destination) {
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Immutable APK already exists with different bytes. Increase versionCode.' }
} else { Copy-Item -LiteralPath $apkFile.FullName -Destination $destination }
[IO.File]::WriteAllText("$destination.sha256", "$hash  relic-diver-$code.apk`n")
$metadata = [ordered]@{ versionCode=$code; versionName=$versionName; gameProtocol=$protocol; minimumOnlineVersionCode=$MinimumOnlineVersionCode; downloadUrl='/downloads/android/'; bytes=$apkFile.Length; sha256=$hash; signingFingerprint=$fingerprint; notes=$Notes }
$stable = Join-Path $Output 'stable.json'
[IO.File]::WriteAllText("$stable.tmp", ($metadata | ConvertTo-Json))
Move-Item -LiteralPath "$stable.tmp" -Destination $stable -Force
"Staged Android build $code ($versionName) locally. No files published."
"SHA-256 $hash"
"Signing fingerprint $fingerprint"
