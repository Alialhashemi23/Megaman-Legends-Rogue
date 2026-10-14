# Next features: original brief (implemented in pass 16)

**Status:** implemented on `codex/next-features-volnutt`; see [FEATURE-REPORT.md](../FEATURE-REPORT.md). The brief below is retained for rationale. The current user requested branch review and later merge, so its deployment instructions do not apply to this pass. Difficulty tuning awaits human feedback.

Written 2026-10-13 at the end of pass 12. The user agreed to everything here ("the asks I all agree to") and asked for it to be handed to another agent to build while they play. Nothing below is started. Read `HANDOFF.md` first for the state of the project, then only the subsystem handoffs you need.

Build the features in the order given: the skill trees depend on what each character can do, and saving depends on what the skill trees store.

## Ground rules

- Repository: `D:\code repos\Megaman-Legends-Rogue` on the user's Windows PC, branch `main` (`online-coop` points at the same commit). Commit and push when a feature is complete and verified.
- The game is live at https://megaman.galosengen.dev, served from this PC by Docker. The user may be playing while you work. Redeploying restarts the server and drops online lobbies, so deploy once per finished feature, not per edit, and tell the user to refresh.
- Rebuild and deploy after gameplay changes:
  ```powershell
  .\tools\package-web.ps1
  .\tools\Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-pack 'Windows Desktop' build/RelicDiver.pck
  .\tools\package-windows.ps1
  docker compose up -d --build relic-diver
  ```
  Then check `https://megaman.galosengen.dev/healthz` and that `index.pck` on the site has the same size as `build\web\index.pck`.
- Bump `NET_VERSION` in `scripts/net.gd` whenever two builds would disagree about the world or the messages (new weapons, changed robot counts, new synced state). Bump `CHECKPOINT_VERSION` in `scripts/game.gd` when saved digs from the old build would restore wrongly.
- Co-op must keep working. The host simulates robots; each digger owns their own movement, Life and build; the shooter decides robot damage and the victim decides digger damage. Floor generation must stay deterministic from the seed. See `docs/handoff/NETWORK.md`.
- Keep the Legends look and feel described in `DESIGN.md`. Never commit `.env`, saves or tokens.
- Tests to run after each feature: `tests/character_checks.gd`, `combat_checks.gd`, `ui_checks.gd`, `options_checks.gd`, `run_resume_checks.gd`, `audio_checks.gd`; the `--smoke-test`, `--combat-test` and `--movement-test` modes; `npm test` in `server/`; and `tests/net_test.sh` through Git Bash. Update tests that encode old numbers rather than deleting them.

## 1. Individual attacks per character

**Goal:** each digger attacks in a way that fits the character, instead of all four sharing the three busters.

**Agreed direction:**

| Digger | Attack | Extra |
|---|---|---|
| Mega | Pulse Buster, the all-rounder (unchanged) | None |
| Roll | The Needle Buster's rapid fire | A support ability: faster revives, or a repair drone that heals nearby diggers |
| Tron | The heavy Siege shots, or commands a few Servbots that fight beside her | To be designed with the attack |
| Servbot | Throws bombs in an arc | Small and fast, with low Life |

The user suggested handing Mega's existing buster options to the other characters, which is what this table does.

**Also part of this feature:** give the Servbot a smaller collision capsule and a lower camera. Today it is about 1.1 m tall but uses the full-size capsule (`scripts/player.gd`, capsule height 1.8) and camera pivot (`update_camera`, 1.55 m), so shots that look like they pass over its head still hit.

**Open question (not answered by the user):** does each character have one fixed weapon, or a small set of their own to unlock? If the user is unavailable, build one signature weapon per character and leave room for more; that is the smaller change and the skill tree can add the rest.

**Where the code is:**
- `scripts/player.gd`: `shoot()`, `fire_delay()`, `damage()`, weapon index `weapon` (0 Pulse, 1 Needle, 2 Siege).
- `scripts/bolt.gd`: projectiles, including the heavy splash shot. A bomb needs an arcing projectile; nothing arcs today.
- `scripts/character.gd`: `DiverCharacter` (`COUNT`, `IDS`, per-character buster colour and scale), the aim layer and the muzzle. The Servbot has no forearm joint.
- `scripts/hud.gd`: the title screen's SELECT BUSTER panel, the lobby's buster row, and `digger_card`. Buster unlocks are currently gated by total kills (10 for Needle, 50 for Siege) in several places; search for `meta.kills >=`.
- `scripts/game.gd`: `selected_weapon`, `build_state()`/`apply_build()` (what is synced and checkpointed per digger), `M_SHOT` handling for teammates' cosmetic shots.
- Sounds: `scripts/sound.gd` `EFFECT_NAMES`; new effects need files under `assets/audio/sfx/`.

**Watch for:** guests replay teammates' shots cosmetically from `M_SHOT`, which only carries position, direction and a heavy flag. New projectile types need that message widened (and `SHAPES` in `game.gd` updated). Summoned Servbot helpers would be new host-simulated actors that need syncing to guests and to late joiners; that is the most expensive option in the table.

## 2. Skill trees and a currency

**Goal:** deepen the roguelite loop. After a run the player spends a Mega Man-themed currency on a skill tree for each character, and the unlock gates get higher with more to unlock.

**Agreed direction:**
- **Currency:** zenny. Earn it at the end of a run from depth reached, guardians beaten and leftover scrap.
- **Spending:** a shop screen after the results screen, with one tree per character.
- **Gating:** raise the gates on the existing unlocks and add more things to unlock.

**Open question (not answered by the user):** do the trees grant permanent power, or only sidegrades and new abilities? `DESIGN.md` pillar 5 currently says persistent progress widens the pool and never adds starting damage or Life, so permanent power changes the design. If the user is unavailable, build the tree so nodes are mostly new abilities and options with a few modest stat nodes, keep the numbers in one table so they are easy to retune, and update pillar 5 to say what was built. Rescale the difficulty in `scripts/enemy.gd` (`hit()`, `pace()`, Life in `_ready`) if stat nodes make runs easy again.

**Where the code is:**
- `scripts/game.gd`: `meta` (kills, runs, wins, deepest, best_time, discovered), `load_meta()`/`save_meta()`, `finish_run()`, `ITEMS` with per-item `unlock` kill thresholds, `pool()`.
- `scripts/hud.gd`: the results screen (`mode == "end"`), the Parts Collection (`archive`) screen, and the menu helpers (`window`, `button`, `hits`, focus navigation, controller support). A new screen needs a mode in `MENU_MODES` and navigation for mouse, keyboard and controller.
- Online: unlocks are per player and are not shared. Decide what a tree node does in co-op and send anything that affects combat through `build_state()` so teammates and the host see it.

## 3. Saving

**Goal:** roguelite progress must not be lost on a refresh.

**Current state:** progress already survives a refresh. The web build saves `meta` to `user://` (IndexedDB) and the Windows build to `save/archive.json`. It does not survive clearing site data, another browser or device, or a domain change.

**Agreed direction:** keep browser storage and add an **export/import save code** (a string the player can copy out and paste back in, from the Options or Parts Collection screen). Server-side saves with logins are only worth building if the user later wants progress to follow players between devices automatically; the server currently stores nothing on disk.

**Do:**
- Put zenny, tree purchases and any new unlocks in the same saved record, with a version number, and migrate old saves instead of resetting them. The user's existing progress must carry over.
- Save immediately on every purchase and at the end of every run, not only on exit.
- Validate imported codes and refuse damaged ones without touching the existing save.
- Add checks alongside `--persistence-test` and `tests/run_resume_checks.gd`.

## Smaller agreed items

- **Zoomed minimap:** the map now fits the whole floor into its box (`map_at` in `scripts/hud.gd`), so rooms are small. Offer a zoomed version that scrolls with the player, either as an Options toggle or in place of the fitted one.
- **Difficulty tuning:** the pass-12 numbers are a first pass. The user's feedback before that pass was that the game was too easy, they liked the telegraphs and raid-style mechanics, and wanted them faster rather than removed. Adjust after they report back.
- **Not yet checked from pass 12:** nobody has played the new rooms, characters or loading screen in a real browser from start to finish, and `tests/web_e2e.mjs` has not been run on this PC (it needs Playwright).
