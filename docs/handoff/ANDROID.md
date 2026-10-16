# Android handoff

Native Godot export for the Retroid Pocket 5 (Android 13, Snapdragon 865, 5.5" 1080p). Phases 2 and 5; app id `dev.galosengen.relicdiver`, ARM64, landscape, Compatibility renderer, no WebView. Phase 5 and its phase 4 dependency are merged into `main` through `dec0ddc` with the owner's approval. Phase 5 has not been deployed live.

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

## Phase 5 implementation (2026-10-14)

- Android signs in from the in-game panel (email/password, then an authenticator code if enabled; APK 5 / 0.19.0 onward) and keeps the `set-auth-token` bearer. Builds 2–4 used `relic-android` device-code login, which the server still accepts. API calls use the bearer, plus account lobby tickets. Run starts identify the platform as `android`. Windows stays memory-only; Android encrypts the bearer with AES-256-GCM and a non-exportable Android Keystore key via Godot's built-in Java bridge. Ciphertext is isolated per server origin with origin-bound authenticated data. No plaintext persistence fallback; unavailable storage keeps only the current process session and reports that sign-in is needed after restart. Sign-out removes ciphertext.
- Startup restores the token but loads authoritative cloud progress before play/spending. Expired or unreadable saved sessions ask for sign-in or an explicit Guest choice. Pause persists the outbox and run checkpoint; resume refreshes the profile outside a dig/lobby. Signing in no longer leaves the app.
- A five-second, size-limited boot metadata check offers controller-accessible Update available / Download update / Later. Minimum build or protocol mismatch gates co-op, while Guest solo remains available. Only an explicit choice outside a dig/lobby opens the same-origin HTTPS download page. Metadata failure doesn't block Guest solo. APK bytes are not read/verified by the client; Android checks install signatures.
- Credits / Licenses is accessible from the title and paginates the full project, Godot, Capcom asset, audio and font notices packaged under `assets/notices/`.
- APK versionCode **3**, versionName **0.18.0**, debug/test-signed ARM64 and x86_64 builds created locally. Protocol 7, checkpoint 3 and profile 2 unchanged. Production signing key remains an owner input. [ANDROID-UPDATES.md](../ANDROID-UPDATES.md) explains local staging and opt-in hosting; no APK or update metadata was published live.

Checks: `tests/android_checks.gd` (44), account (34), UI (47), Node Android-update/relay tests (10). `tools/test-android-vault.ps1` creates a unique disposable app and validates Keystore encryption/decryption, no plaintext on disk, origin separation, tamper rejection, sign-out, process restart and higher-version in-place upgrade. Full emulator game startup at build 3 passed without script errors. The native probe passed 9 checks on restart and upgrade. No real account credentials were used in those probes.

**Readiness fixes (2026-10-14, merged into `main`, APK build 4 / 0.18.1):**
- Choosing Play as Guest while a saved session is still restoring (typically an offline boot) used to sign out, erasing the Keystore session and revoking it. It now keeps the encrypted session; Account → Sign In retries it before asking for a new code. Explicit Sign Out still erases it.
- Offline/5xx/429 restores retry every 15 seconds instead of waiting for Retry or an app resume.
- An invalid server profile during sign-in/restore stays `restoring` (digs, purchases and server changes blocked) instead of `signed_in` with no profile while Guest progress showed.
- A restored profile only jumps to the Account page from the title/account screens, not from Options or the Workshop.
- If the browser cannot be opened for an update, the prompt stays with the URL instead of being dismissed.
- Android checks 44 → 49 (all pass); account and UI checks pass. Web ZIP, Windows pack/ZIP refreshed. Local test-signed APKs: `build/RelicDiver-android.apk` code **4** (SHA-256 `417329aa78275f1bd4393ae5ff9a258e3b0815bd6cf3a344dadea02a5916d014`) and the previous code-3 build kept as `build/RelicDiver-android-3.apk` (`f071e7a4…`) for the in-place upgrade test. Not published. The x86_64 emulator APK was not rebuilt.

Owner hardware checklist: [RETROID-CHECKLIST.md](RETROID-CHECKLIST.md).

Still required on real hardware: end-to-end device approval with browser switching, account cache/outbox recovery and cross-device earned progress; full Retroid/browser/Windows co-op; wrong signing key/no space/cancelled download/sleep during download; update preserving actual game progress/settings/account access. No claims of Retroid validation, live Android downloads or production signing.

Additional emulator checks passed: Android rejected a wrong-key update of the disposable probe (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); upgrading the full game APK from code 2 to 3 preserved the existing Guest archive's SHA-256 exactly. Local release staging rejected changed APK bytes under an already staged code. No-space, cancellation and sleep-during-download installer cases were not exercised.

## Toolchain details

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

Public releases: `tools/package-android.ps1 -Release` with the release keystore (see HANDOFF.md, "Public release"), uploaded to a GitHub Release as `RelicDiver-android.apk`. Debug/test builds use a different key, so installing a release over one needs an uninstall first.

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
- **Implemented in phase 5:** in-game credits/licence page, Keystore-backed session storage and startup update checking. Hardware/installer acceptance remains open as above.
- The title screen still has a **Quit** button, which is harmless on Android.
