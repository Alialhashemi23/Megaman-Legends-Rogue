# Online co-op and web build handoff

Pass 09 added browser play and online co-op for up to four diggers. The user requested lobbies, invite links and a lobby browser on their own domain, hosted themselves through a Cloudflare Tunnel. Pass 10 made runs survive mishaps (the user's priority before any further work) and added co-op communication and lobby controls. The user-facing guide is [../ONLINE.md](../ONLINE.md).

## Topology

- **Relay server** (`server/`, Node 20+, one dependency `ws`). It serves the exported web build with cross-origin isolation headers (the threaded Godot build needs `SharedArrayBuffer`) and pre-compressed brotli/gzip bodies. It upgrades `/ws` to the lobby protocol. Lobbies and the latest host checkpoint per lobby live in memory.
- **Host-authoritative game.** The lobby's host slot (`hostSlot`, *not* always slot 1) simulates robots, pickups, scrap, rooms, interactables and the run outcome. Guests simulate their own digger and cosmetic copies of everything else.
- All traffic goes through the relay over WebSocket (TCP, ordered). Peer-to-peer was rejected to avoid NAT/TURN problems.

## Lobby protocol (server protocol 2, game `NET_VERSION` 2)

Text frames are JSON, handled in `server/lobby.js`, `server/server.js` and `scripts/net.gd`.
- **Client → server:** `hello{name,id,v}`, `list`, `create{name,public,password}`, `join{code,password}`, `resume{code,name,public,password}`, `leave`, `name`, `kick{slot}`, `lock{locked}`, `status{state,depth}`, `ping`.
- **Server → client:** `welcome`, `lobbies`, `joined{code,slot,hostSlot,takeover,checkpoint,recreated,password}`, `lobby{lobby}`, `host{slot}`, `entered{slot,name,id}`, `left{slot}`, `kicked`, `replaced`, `error{code}`, `pong`.

Rules:
- `id` is the player's stable identity (`online.json`, or `--player-id=` in tests).
- A lobby's version is set by its creator. Joiners on another `v` get `error version`.
- **Host leaves:** the lowest remaining slot becomes host (`host` message).
- **Empty lobby:** kept for `RUN_GRACE_MINUTES` (15) during a run, or 3 minutes otherwise. The first player back takes over hosting (`takeover`) and receives the stored checkpoint.
- **Resume after a server restart:** `resume` on an unknown code recreates the lobby under that code (`recreated`).
- **Same identity rejoins:** it replaces the old connection (`replaced`). If the replaced player was host and others remain, hosting moves first.
- **Returning identities** skip the lock and the password. **Kicked identities** are banned from that lobby.

Binary frames are game packets. A client sends `[target][var_to_bytes(Array of messages)]`, where target 0 means everyone else. The server stamps the sender's slot and forwards without inspecting. Target 255 from the host stores the run checkpoint on the server; the server delivers it as a source-255 frame after a takeover `joined`. Message types are the `DiverNet` enum; `SHAPES` in game.gd validates each one, and malformed messages are dropped and counted. Floor-tied messages carry the descent number first.

| Owner | Messages |
|---|---|
| Every digger → all | `M_INFO{build}` (full build dictionary on every change), `M_STATE` (20 Hz), `M_SHOT`, `M_CHAT`, `M_PING` |
| Guest → host | `M_HIT`, `M_INTERACT`, `M_FROST` |
| Host → all | `M_START{seed,party,run_id}`, `M_FLOOR`, `M_END`, `M_SNAP`, `M_ATTACK`/`M_RESOLVE`, `M_DAMAGE`, `M_DIE`, `M_LIGHTNING`, `M_PICKUP`/`M_PICKUP_GONE`, `M_USED`, `M_CLEARED`, `M_CHOICE`, `M_RESTORE`, `M_XP`, `M_NOTIFY` |
| Host → one | `M_SYNC{world, build}` (any joiner; `build` is their saved build if their identity is known), `M_ITEM`, `M_HEAL`, `M_NOTIFY` |

## Authority rules (keep these when changing combat)

- **Deterministic generation.** `start_run` seeds with the run seed; descents reseed with `floor_seed(depth)` (plain integer math, identical in native and WebAssembly). Party size is part of the input. Robot ids are their `game.enemies` index.
- **Victim decides digger damage.** Robot windups and resolves replay everywhere, and each machine checks hits only against its own `game.player`. Robot AI uses `target_for()`/`sees()`.
- **Shooter decides robot damage.** Guests send `M_HIT`; the host applies it with the shooter's mirrored parts.
- Teammate proxies are `DiverPlayer` with `is_local = false` on collision layer 8.
- **Downed/revive is decided by the downed digger.** The host ends the dig when every digger reports down.
- Online menus don't pause. `game.world_running()` is false while reconnecting (the dig freezes for that player until the resync).

## Persistence model (pass 10)

- `build_state()`/`apply_build()`: character, buster, parts, level, XP, base stats, Life, downed, the open choice (kind + offered items) and queued choices.
- `world_state()`/`apply_world_state()`: run id, seeds, depth, party, scrap, kills, time, guardian flag, living robots (id, health, position, active), used interactables, cleared/visited rooms, pickups. A world is rebuilt from its floor seed, then the differences are applied. `build_floor(keep, arrive=false)` avoids the lift's free healing on restores.
- **Roster.** Every machine mirrors every digger's build by identity from `M_INFO` (Life/downed from `M_STATE`). Whoever hosts returns a known identity's build in `M_SYNC`.
- **Checkpoint** = `{v, online, lobby_code/name/public/password, run_id, world, build, roster, selected}`.
  - Saved with `store_var` every 5 s and 0.5 s after any build change, via a temp file then rename. A corrupted file is ignored, and a leftover `.tmp` is the fallback.
  - The host also uploads each save to the server.
  - Paths: web `user://run_checkpoint.dat`, desktop `res://save/run_checkpoint.dat`, override `--checkpoint-path=`. Bump `CHECKPOINT_VERSION` if the format changes.
- **Takeover:** the newest of the server copy and the local copy (same run → larger run time) wins. A live, rejoining digger keeps its own fresher build. `finish_run` clears the checkpoint. A replaced saved dig is "retired": its machines go into the record.
- **Host migration** (`become_host`): robots start from their last snapshot positions, and pickup ids jump past anything seen.
- **Web:** `onbeforeunload` asks before leaving during a dig or lobby. Invite links carry `&key=` for password lobbies. Opening an invite link whose code matches a saved dig resumes it.

## Co-op communication and controls

- `say()`/`M_CHAT`: T or Enter in the dig, a field in the lobby room. `ping_here()`/`M_PING`: G or middle mouse, labelled by what it hits.
- Quick chat (1–4) adds a speech bubble (`DiverPlayer.speak`). `spectate_target()` drives the downed camera; click cycles.
- HUD: `CONFIRM` actions need a second click within 3 s. The lobby room shows Remove buttons, Lock/Unlock and the password for the host.

## Files

- `scripts/net.gd`: transport, identity, host slot, reconnect loop, checkpoint upload, lobby commands, invite links.
- `scripts/game.gd`: online section at the bottom (snapshots, checkpoints, takeover/migration, message validation and handling, chat/pings/spectating), plus hooks in `start_run`, `build_floor`, `update_world`, `interact`, choices, pickups and `_process` (autosave, page guard).
- `scripts/player.gd`: proxy mode, state flags, downed/revive, spectator camera, speech bubbles. `scripts/enemy.gd`: targeting, proxy mode, attack/damage/death events.
- `scripts/hud.gd`: Play Online browser (passwords, locks), lobby room (kick, lock, chat), team panel, chat, reconnecting overlay, Continue/Rejoin Dig, confirmations.
- `server/`, `docker-compose.yml`, `.env.example`, `Host-Online.cmd`, `tools/package-web.sh`/`.ps1`.

## Checks

```sh
cd server && npm test                                     # 9: lobby rules, migration, grace, takeover, replace, kick/lock/password/version, resume
godot --headless --path . --script tests/run_resume_checks.gd   # 24: exact restore, damaged files, retiring, network fuzzing
tests/net_test.sh /path/to/godot                           # 7 processes: co-op play, guest refresh, Wi-Fi drop, host crash + migration,
                                                           # host return, empty-lobby resume, server-restart resume
xvfb-run godot --path . --script tests/coop_preview.gd     # renders screenshots/coop-*.png
PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/web_e2e.mjs [shots]   # real browser: lobby, invite, guest reload, host reload + migration
```

The browser test needs one browser process per player: two Godot tabs in one headless Chromium starve each other under software WebGL.

## Known limits

- Rejoining or migrating can roll robots back to their last snapshot positions, and a takeover from a checkpoint can lose up to about 5 seconds.
- No client-side prediction for robots. Guests see them about half a round trip late, but warnings keep the same reaction window.
- A web build over plain HTTP on a LAN IP can't start (no secure context). Use `localhost` or the HTTPS domain.
- Trust model: friends co-op. The host clamps reported damage and validates message shapes, but a modified client could still cheat in its own lobby.
