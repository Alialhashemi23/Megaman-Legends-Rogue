# Android accounts and updates

Build 3 (`0.18.0`) introduces Android device approval, Keystore-backed saved
sessions and startup update checks. It keeps app id `dev.galosengen.relicdiver`,
game protocol 7, checkpoint 3 and profile 2. Guest solo remains available offline.
Current APKs are development/test-signed and have not been published.

## Local builds and tests

`tools/package-android.ps1` builds ARM64; `-Emulator` builds x86_64. Use the same
signing key and increase `version/code` for every distributed upgrade. Never
uninstall to update: uninstalling erases app data and its Keystore keys.

`tools/test-android-vault.ps1` requires the existing configured toolchain and a
running emulator. It builds a unique disposable test app, checks encryption,
tampering, sign-out, process death and an in-place upgrade, then uninstalls only
that app. It leaves ignored logs/APKs under tools for diagnosis. It never uses
real sessions or modifies the game app's saves. Client update decisions live in
`tests/android_checks.gd`; server metadata/compatibility in
`server/test/android-updates.test.js`.

## Stage an update (does not publish)

```powershell
.\tools\prepare-android-release.ps1 -Apk build/RelicDiver-android.apk `
  -Notes 'Describe the changes here.' -MinimumOnlineVersionCode 2
```

The script reads the APK's real package id, version code/name and signing
certificate through Android build tools, verifies its signature, computes the
byte size/SHA-256 and reads the game protocol from source. It writes ignored
`build/android-release/stable.json`, `relic-diver-3.apk` and its checksum.
An existing versioned APK with different bytes is rejected: increase the code.
Retain older versioned files and the signing key for in-place updates.

Metadata fields: integer `versionCode`, `gameProtocol`,
`minimumOnlineVersionCode`, `bytes`; strings `versionName`, `downloadUrl`,
`sha256`, `signingFingerprint`, `notes`. `downloadUrl` is `/downloads/android/`;
the client resolves it against its configured HTTPS origin. Hash/fingerprint
are 64 hexadecimal characters. The minimum cannot exceed the latest code.
There is no version-string ordering and no automatic downloader/installer.

## Hosting (requires owner request)

Set ignored `.env` `ANDROID_RELEASE_HOST_DIR` to the staged release directory
and explicitly add `docker-compose.android.yml` alongside the base/accounts
Compose files when deploying. The directory is mounted read-only, and
`ANDROID_RELEASE_DIR=/app/android-releases` enables these server routes:

- `/updates/android/stable.json`: no-store metadata, 404 while absent/invalid.
- `/downloads/android/`: no-store download page with full notes, bytes, APK
  hash, signing fingerprint and an instruction to install over the existing app.
- `/downloads/android/relic-diver-N.apk` and `.apk.sha256`: immutable files.

Nothing copies APKs into the normal web ZIP or deploys by default. Back up the
production signing key before distributing a release. Test keys do not provide
a production update promise. Never commit keystores, signing passwords or
account sessions. A new signing key cannot replace an installed app signed with
another key; leave the installed app intact if Android refuses an upgrade.

The client offers Later for compatible builds and solo/update-later for an
online-incompatible build. The relay rejects self-identified Android clients
below the configured minimum or with another game protocol; these hello fields
are compatibility hints, not attestation. Pre-phase-5 clients did not identify
their platform, so cannot be distinguished reliably from old desktop clients.
Missing metadata leaves the relay's existing lobby protocol checks in place.

## Acceptance still requiring the owner

Real Retroid approval/resume/restart/upgrade with earned account progress;
browser/Windows cross-play; cancel/no-space/wrong-key/sleep installer scenarios;
production signing and owner-approved publication. Emulator results do not
establish handheld performance or hardware-backed key security level.

Implementation follows Godot's [Android Java bridge](https://docs.godotengine.org/en/4.7/tutorials/platform/android/javaclasswrapper_and_androidruntimeplugin.html)
and Android's [Keystore guidance](https://developer.android.com/privacy-and-security/keystore).
