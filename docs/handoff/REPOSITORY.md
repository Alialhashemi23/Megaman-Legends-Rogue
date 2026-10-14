# Repository and packaging handoff

Authorized remote: https://github.com/Alialhashemi23/Megaman-Legends-Rogue (origin, main). The user explicitly requested committing the existing game, design and handoffs here, superseding the earlier no-repository preference. This is not authorization to deploy a hosted game or publish elsewhere.

`main` is the integration branch (the user chose it over creating `master`). New work goes on a feature branch per [ROADMAP.md](ROADMAP.md) phase and merges into `main` with the user's approval. `online-coop` and `codex/next-features-volnutt` are historical branches already contained in `main`. Future database/auth backups, activity records, session credentials and Android signing keys must remain outside Git and distributed packages.

## What belongs in Git

Godot project configuration, scripts, tests, runtime assets, editable artwork, original model sources/archives and converter, original audio composition/MIDI sources, required bank/renderer sources and licenses, screenshots authored locally, documentation and a compressed Windows playable bundle. Keep credits and asset license exceptions with the project.

Ignore .godot caches, personal save profiles, backups, Python caches, runtime logs, raw movie captures, machine-specific browser wrappers and loose large engine executables. Their local files remain intact. The original engine executable exceeds GitHub's per-file limit, so build/RelicDiver-Windows.zip preserves the executable plus pack and notices in a smaller archive. Do not accidentally stage duplicate runtime copies or old build backups.

The SoundFont and FluidSynth are authoring tools; the game itself plays finished audio. Original character ZIPs are provenance and editable input, not an additional runtime requirement. assets/characters/*.glb and rendered portraits are the files actually used by Godot.

## Android build

`tools/package-android.ps1` produces `build/RelicDiver-android*.apk`; APKs, keystores (`*.keystore`, `*.jks`) and `.idsig` files are git-ignored and never tracked. The toolchain and signing keys live outside the repo (see [ANDROID.md](ANDROID.md)).

## Web build and server

`build/RelicDiver-Web.zip` is the tracked browser bundle (game files plus notices); the loose `build/web/` export is ignored. `server/` holds the lobby relay and static host (`node_modules` ignored). The root `docker-compose.yml`, `.dockerignore`, `.env.example` and `Host-Online.cmd` deploy it. `.env` carries the user's Cloudflare Tunnel token and must never be committed. The user runs the deployment on their own machines and domain.

## Build handling

Use the pinned engine version when rebuilding. Export the content pack, refresh build notices/docs, recreate the ZIP with the executable, console helper, pack, README, CHANGELOG, licenses and character/audio credits. Exclude save/ and preview/ from that archive. Keep the previous good build locally if a change is risky.

tools/setup-runtime.ps1 sets up a fresh Windows clone from the committed bundle; no download is required. It does not overwrite player saves. Play.cmd and Edit.cmd prefer an existing tools/ engine and otherwise invoke setup. See TECHNICAL.md for validation and export commands.

## Ownership

Original source code, locally authored environment/UI work, animation authoring and original compositions/effect synthesis are covered by LICENSE.md. Capcom character meshes, textures, rigs, derived portraits and GLBs are excluded from MIT. Preserve Models Resource provenance and Xinus23 credits. GeneralUser samples, FluidSynth, fonts and Godot retain their upstream notices. Do not claim non-profit status transfers ownership or grants a blanket asset license.

## Context efficiency

Keep HANDOFF.md current after meaningful changes: what shipped, tests actually run, unresolved issues and the next user request. Update DESIGN.md when an accepted design decision changes. Put subsystem detail in the relevant handoff, not in a giant conversation transcript. Do not commit credentials, personal profiles or local usage/account data.
