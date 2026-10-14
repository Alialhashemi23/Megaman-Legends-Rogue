# Android handoff

Native Godot export for the Retroid Pocket 5 (Android 13, Snapdragon 865, 5.5" 1080p). Roadmap phase 2; accounts and the update check come in phase 5. App id `dev.galosengen.relicdiver`, ARM64, landscape, Compatibility renderer, no WebView.

## Status

Built and verified on the Android emulator. **Not yet verified on the Retroid** (no hardware has been available), so frame rate, heat, battery, real controller mappings and the soft keyboard are open.

| Verified on the emulator (x86_64, Android 15, host GPU) | Result |
|---|---|
| APK builds, signs (v2/v3 verified), manifest: id, ARM64, Internet + network-state only | Yes |
| Title screen, menus, fonts, all four diggers listed, models and textures | Renders correctly |
| Solo dig: HUD, pause menu, Leave Dig records the run | Yes; profile written to the app's private `files/archive.json` |
| In-place update (`adb install -r`) keeps progress | Yes ("1 digs" after the update) |
| Play Online reaches `wss://megaman.galosengen.dev/ws`, creates a lobby | Yes (77 ms) |
| Backgrounding (Home) then returning | Connection dropped, auto-reconnected and rejoined the same lobby and slot |

Screenshots: `screenshots/android-emulator-*.png`.

## Toolchain

Versions follow Godot 4.7's Android export guide; recheck it when the engine version changes. Everything lives outside the repo in `D:\Android` (override with `RELIC_ANDROID_TOOLCHAIN`):

| Piece | Version | Location |
|---|---|---|
| JDK | Temurin 17 | `D:\Android\jdk\<jdk>` |
| Android SDK | platform 35, build-tools 35.0.1, platform-tools, NDK 28.1.13356709, CMake 3.10.2.4988404 | `D:\Android\sdk` (installed with `sdkmanager --licenses`, which accepts Google's SDK license) |
| Godot templates | 4.7.1.stable `android_debug.apk`, `android_release.apk`, `android_source.zip` | `%APPDATA%\Godot\export_templates\4.7.1.stable` |
| Debug key | `androiddebugkey`, password `android` | `D:\Android\debug.keystore` (create with `keytool -genkeypair -keystore ... -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 9999 -storepass android -keypass android`) |
| Emulator (optional) | emulator + `system-images;android-35;google_apis;x86_64`, AVD `relic35` | `D:\Android\avd` |

On a fresh PC: unzip the JDK and the command-line tools under those folders, run `sdkmanager --sdk_root=D:\Android\sdk` for the packages above, and extract the three `android_*` files from `Godot_v4.7.1-stable_export_templates.tpz` into the template folder.

## Building

```powershell
.\tools\package-android.ps1             # build/RelicDiver-android.apk (ARM64, debug-signed)
.\tools\package-android.ps1 -Emulator   # build/RelicDiver-android-x86_64.apk, for the emulator only
.\tools\package-android.ps1 -Release    # needs GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
```

The script gives Godot its own editor-settings folder (`D:\Android\godot-config`, with a junction to the installed templates) so your editor configuration is untouched. It prints the APK's size and SHA-256. `-Emulator` swaps the preset to x86_64 for the export and restores it. APKs, keystores and `.idsig` files are git-ignored.

The preset (`export_presets.cfg` preset 2) sets `version/code` and `version/name`. **Raise `version/code` for every build you hand to someone**, since Android only updates in place to a higher code. The debug key is for development: a release build needs a securely backed-up key, and the app id must not change once a signed build is distributed.

Running on a device or emulator:

```powershell
D:\Android\sdk\platform-tools\adb.exe install -r build\RelicDiver-android.apk
D:\Android\sdk\platform-tools\adb.exe shell monkey -p dev.galosengen.relicdiver -c android.intent.category.LAUNCHER 1
D:\Android\sdk\platform-tools\adb.exe logcat -s godot
```

On the Retroid, enable developer options and USB debugging, or copy the APK over and allow installs from the file manager.

## What changed in the game

- **Saves:** `scripts/paths.gd` (`DiverPaths`) chooses where profiles, settings, audio settings, online identity and checkpoints live. Desktop keeps the portable `res://save/` folders; web and Android use `user://` (Android: `/data/data/dev.galosengen.relicdiver/files/`). Add new persistent files through `DiverPaths.pick(portable, sandbox)`.
- **Display:** `window/handheld/orientation=4` (sensor landscape) and ETC2/ASTC texture import are enabled in `project.godot`. Fullscreen toggling is skipped on Android, and the "Click to take aim" overlay is hidden.
- **Packaging:** the export filter matches the Windows preset (tools, tests, saves, server and docs are excluded). The only permissions are Internet and network state.

## Known limits and open work

- **The emulator is not the Retroid.** The emulator's software GPU (`swiftshader_indirect`) fails to link some shaders (261 fragment uniform vectors); that is an emulator limit and does not happen with a real GPU (`-gpu host`). Real Adreno 650 limits are much higher, but only the device can confirm performance.
- **Needs the Retroid:** controller mappings and the pad prompts, text entry (name, lobby code, server, save codes), 60 FPS and thermals over a full run, readable text at 5.5", docked display, sleep and process death, a full co-op dig with a browser and Windows player (late join, host migration both ways).
- **Controller prompts:** menus show keyboard prompts until a controller button is pressed once; nothing detects a controller at startup.
- **Not built yet:** an in-game credits/licence page (needed before any distributed build, since the APK carries Capcom's character assets and the licence notices must travel with it), secure token storage and the update check (phase 5).
- The title screen still has a **Quit** button, which is harmless on Android.
