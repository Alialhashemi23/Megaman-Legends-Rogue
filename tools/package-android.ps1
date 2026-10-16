# Export the Android APK (ARM64, non-Gradle) to build/RelicDiver-android.apk.
#   tools\package-android.ps1            development build, signed with a debug key
#   tools\package-android.ps1 -Release   release build, needs your own release keystore
#   tools\package-android.ps1 -Emulator  x86_64 debug build for the Android emulator (not for devices)
#
# Toolchain (see the README's developer notes): JDK 17, Android SDK with platform 35,
# build-tools 35.0.1, NDK 28.1.13356709 and CMake 3.10.2, plus Godot's 4.7.1
# Android export templates. Signing keys and passwords never live in the repo:
# they come from environment variables or the toolchain folder.
[CmdletBinding()]
param(
    [switch]$Release,
    [switch]$Emulator,
    [string]$Toolchain = $(if ($env:RELIC_ANDROID_TOOLCHAIN) { $env:RELIC_ANDROID_TOOLCHAIN } else { 'D:\Android' }),
    [string]$Godot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools/Godot_v4.7.1-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$jdk = Get-ChildItem -LiteralPath (Join-Path $Toolchain 'jdk') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $jdk) { throw "No JDK 17 under $Toolchain\jdk. Install it there or set RELIC_ANDROID_TOOLCHAIN." }
$sdk = Join-Path $Toolchain 'sdk'
foreach ($need in @('platform-tools\adb.exe', 'build-tools\35.0.1', 'platforms\android-35', 'ndk\28.1.13356709')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sdk $need))) { throw "Android SDK is missing $need under $sdk." }
}
$templates = Join-Path $env:APPDATA 'Godot/export_templates/4.7.1.stable'
foreach ($name in @('android_debug.apk', 'android_release.apk', 'android_source.zip')) {
    if (-not (Test-Path -LiteralPath (Join-Path $templates $name))) { throw "Missing Godot Android template $name in $templates." }
}
$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
# Godot reads the SDK/JDK/keystore paths from its editor settings, not the environment.
# Give this export its own settings folder so the user's editor configuration is untouched,
# and reuse the installed export templates through a junction.
$realTemplates = Split-Path -Parent $templates
$config = Join-Path $Toolchain 'godot-config'
$configGodot = Join-Path $config 'Godot'
New-Item -ItemType Directory -Force -Path $configGodot | Out-Null
$linkPath = Join-Path $configGodot 'export_templates'
if (-not (Test-Path -LiteralPath $linkPath)) { New-Item -ItemType Junction -Path $linkPath -Target $realTemplates | Out-Null }
$debugStore = Join-Path $Toolchain 'debug.keystore'
$settings = @(
    '[gd_resource type="EditorSettings" format=3]', '', '[resource]',
    ('export/android/java_sdk_path = "{0}"' -f $jdk.FullName.Replace('\', '/')),
    ('export/android/android_sdk_path = "{0}"' -f $sdk.Replace('\', '/')),
    ('export/android/debug_keystore = "{0}"' -f $debugStore.Replace('\', '/')),
    'export/android/debug_keystore_user = "androiddebugkey"',
    'export/android/debug_keystore_pass = "android"')
Set-Content -LiteralPath (Join-Path $configGodot 'editor_settings-4.7.tres') -Value $settings -Encoding utf8
$env:APPDATA = $config
$env:LOCALAPPDATA = $config
$buildPath = Join-Path $projectRoot 'build'
if ($Emulator -and $Release) { throw '-Emulator builds are debug only.' }
$apk = Join-Path $buildPath $(if ($Emulator) { 'RelicDiver-android-x86_64.apk' } else { 'RelicDiver-android.apk' })
if ($Release) {
    foreach ($name in @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')) {
        if (-not [Environment]::GetEnvironmentVariable($name)) { throw "Release builds need $name (your release keystore; keep it outside Git)." }
    }
    $mode = '--export-release'
} else {
    if (-not (Test-Path -LiteralPath $debugStore)) { throw "No debug keystore at $debugStore. Create one with keytool (alias androiddebugkey, password android)." }
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $debugStore
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
    $mode = '--export-debug'
}
if (Test-Path -LiteralPath $apk) { Remove-Item -LiteralPath $apk }
# The emulator build swaps the preset to x86_64 for the export only, then restores it.
$presets = Join-Path $projectRoot 'export_presets.cfg'
$presetBackup = [IO.File]::ReadAllText($presets)
try {
    if ($Emulator) {
        $swapped = $presetBackup -replace 'architectures/arm64-v8a=true', 'architectures/arm64-v8a=false' -replace 'architectures/x86_64=false', 'architectures/x86_64=true'
        [IO.File]::WriteAllText($presets, $swapped)
    }
    & $Godot --headless --path $projectRoot $mode Android $apk
} finally {
    [IO.File]::WriteAllText($presets, $presetBackup)
}
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apk)) { throw 'Android export failed. Check the Godot output above.' }
$info = Get-Item -LiteralPath $apk
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash
"{0}  {1:N1} MB  sha256 {2}" -f $info.Name, ($info.Length / 1MB), $hash
