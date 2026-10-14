# Isolated Android Keystore/restart/upgrade test. Requires a running emulator
# and tools/package-android.ps1's configured Godot Android toolchain.
[CmdletBinding()]
param([string]$Toolchain='D:\Android')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$run='r'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$appId="dev.galosengen.relicdiver.vaultchecks.$run"
$probe=Join-Path $PSScriptRoot "vault-checks-$run"
New-Item -ItemType Directory -Path $probe | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'scripts/android_vault.gd') -Destination (Join-Path $probe 'android_vault.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests/android_vault_probe.gd') -Destination (Join-Path $probe 'probe.gd')
Copy-Item -LiteralPath (Join-Path $root 'assets/ui/icon.png') -Destination (Join-Path $probe 'icon.png')
@'
config_version=5
[application]
config/name="Relic Diver Vault Checks"
config/icon="res://icon.png"
run/main_scene="res://main.tscn"
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
'@ | Set-Content -LiteralPath (Join-Path $probe 'project.godot')
@'
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://probe.gd" id="1"]
[node name="Probe" type="Node"]
script = ExtResource("1")
'@ | Set-Content -LiteralPath (Join-Path $probe 'main.tscn')
$preset=[IO.File]::ReadAllText((Join-Path $root 'export_presets.cfg'))
$preset=$preset.Substring($preset.IndexOf('[preset.2]')).Replace('[preset.2]', '[preset.0]').Replace('[preset.2.options]', '[preset.0.options]').Replace('dev.galosengen.relicdiver',$appId).Replace('architectures/arm64-v8a=true','architectures/arm64-v8a=false').Replace('architectures/x86_64=false','architectures/x86_64=true')
$godot=Join-Path $root 'tools/Godot_v4.7.1-stable_win64_console.exe'
$adb=Join-Path $Toolchain 'sdk/platform-tools/adb.exe'
$env:APPDATA=Join-Path $Toolchain 'godot-config'; $env:LOCALAPPDATA=$env:APPDATA
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH=Join-Path $Toolchain 'debug.keystore'
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER='androiddebugkey'; $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD='android'
function Launch-Check {
    & $adb shell monkey -p $appId -c android.intent.category.LAUNCHER 1 | Out-Null
    for($attempt=0; $attempt -lt 40; $attempt++) {
        $probePid=& $adb shell pidof $appId
        if ($probePid) {
            $probePid="$probePid".Trim()
            $logs=& $adb logcat -d --pid=$probePid -s godot
            $result=$logs | Where-Object { $_ -match 'VAULT_PROBE: ([0-9]+) checks, ([0-9]+) failures' } | Select-Object -Last 1
            if ($result) {
                if ($result -notmatch 'VAULT_PROBE: ([0-9]+) checks, 0 failures') { throw "Keystore probe failed: $result" }
                $result
                return
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Keystore probe timed out.'
}
$installed=$false
try {
    foreach($code in @(1,2)) {
        [IO.File]::WriteAllText((Join-Path $probe 'export_presets.cfg'),($preset -replace 'version/code=[0-9]+',"version/code=$code"))
        & $godot --headless --path $probe --editor --import --quit *> (Join-Path $probe 'import.log')
        & $godot --headless --path $probe --export-debug Android (Join-Path $probe "probe-$code.apk") *> (Join-Path $probe "export-$code.log")
        if ($LASTEXITCODE -ne 0) { throw 'Probe export failed; see the local export log.' }
        & $adb wait-for-device
        & $adb install -r (Join-Path $probe "probe-$code.apk") | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Probe install failed.' }
        $installed=$true
        Launch-Check
        if ($code -eq 1) {
            & $adb shell am force-stop $appId
            Launch-Check
        }
    }
} finally {
    # This unique disposable app was created by this run; never uninstall game.
    if ($installed) { & $adb uninstall $appId | Out-Null }
}
