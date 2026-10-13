# Online co-op and web build handoff

Pass 09 added browser play and online co-op for up to four diggers. The user requested lobbies, invite links and a lobby browser on their own domain. They host it themselves through a Cloudflare Tunnel. The user-facing deployment guide is [../ONLINE.md](../ONLINE.md).

## Topology

- **Relay server** (`server/`, Node 20+, one dependency `ws`). It serves the exported web build with cross-origin isolation headers (the threaded Godot web build needs `SharedArrayBuffer`) and pre-compressed brotli/gzip bodies. It upgrades `/ws` to the lobby protocol. Lobbies live in memory; nothing is written to disk.
- **Host-authoritative game.** Lobby slot 1 (the creator) simulates robots, pickups, scrap, rooms, interactables and the run outcome. Guests simulate their own digger and cosmetic copies of everything else.
- All traffic goes through the relay over WebSocket (TCP, reliable, ordered). Peer-to-peer was rejected to avoid NAT/TURN problems; "seamless" joining mattered most.

## Wire protocol

Text frames are JSON lobby commands, handled in `server/lobby.js`, `server/server.js` and `scripts/net.gd`:
`hello{name}`, `list`, `create{name,public}`, `join{code}`, `leave`, `name{name}`, `status{state,depth}` (host only, feeds the browser), `ping`.
Server replies: `welcome`, `lobbies`, `joined{code,slot}`, `lobby{lobby}`, `entered{slot,name}`, `left{slot}`, `closed{reason}`, `error{code}`, `pong`.

Binary frames are game packets. A client sends `[target slot][var_to_bytes(Array of messages)]`, where target 0 means everyone else. The server rewrites byte 0 to the sender's slot and forwards it without inspecting the payload. `DiverNet` batches one packet per target per frame. Each message is `[type, ...]` with types from the `DiverNet` enum. Messages tied to a floor carry the descent number and are dropped if it doesn't match.

| Owner | Messages |
|---|---|
| Every digger → all | `M_INFO` (character, buster, parts, level, name; on change), `M_STATE` (20 Hz pose/velocity/input/flags/Life/revive), `M_SHOT` (cosmetic bolt replay) |
| Guest → host | `M_HIT` (shooter-reported robot damage), `M_INTERACT` (E on interactable index), `M_FROST` |
| Host → all | `M_START{seed,party}`, `M_FLOOR`, `M_END`, `M_SNAP` (20 Hz active robots + scrap/kills/guardian/time), `M_ATTACK`/`M_RESOLVE` (robot windups with fixed aim points), `M_DAMAGE`, `M_DIE`, `M_LIGHTNING`, `M_PICKUP`/`M_PICKUP_GONE`, `M_USED`, `M_CLEARED`, `M_CHOICE`, `M_RESTORE`, `M_XP`, `M_NOTIFY` |
| Host → one | `M_SYNC` (late join), `M_ITEM`, `M_HEAL`, `M_NOTIFY` |

## Authority rules (keep these when changing combat)

- **Generation is deterministic.** `start_run` seeds with the run seed; each descent reseeds with `floor_seed(depth)`. Party size is part of the input (extra robots per room, health scaling), so it travels with `M_START`/`M_FLOOR`/`M_SYNC`. Robot ids are their index in `game.enemies`. Never consume `game.rng` between `build_floor` steps on only one machine.
- **Victim decides digger damage.** Robot warnings and resolves are replayed on every machine. Each machine checks hits only against its own `game.player` (`has_sight()`, `blast()`, beams, melee, charge contact and hostile bolts). Robot AI picks targets with `target_for()` and `sees()`.
- **Shooter decides robot damage.** Guest bolts collide with robot proxies locally and send `M_HIT`. The host applies `take_damage(amount, true, source_proxy)`, so part effects (prism, ember, coil, moss, clover) use the shooter's mirrored parts.
- Teammate proxies are `DiverPlayer` with `is_local = false` on collision layer 8. Robots and local movement ignore them; hostile bolts stop on them without dealing damage.
- **Downed/revive is decided by the downed digger.** They watch their own proxies of teammates. The host ends the run when every digger reports down.
- Online menus and choices don't pause. `game.world_running()` replaces the old `mode == "play"` checks. Choosing a part protects the chooser, and robots deprioritise them.

## Persistence

On the web, saves use `user://` (IndexedDB): `archive.json`, `audio.json`, `online.json` (name; desktop also stores its server URL). Desktop keeps `res://save/`. Each player's unlocks are their own. Co-op runs credit the whole team's machine count to everyone.

## Files

- `scripts/net.gd`: transport, lobby state, invite link and URL handling, profile.
- `scripts/game.gd`: online section at the bottom (message handling, sync, revive/ending rules), plus hooks in `start_run`, `build_floor`, `update_world`, `interact`, pickups and bolts.
- `scripts/player.gd`: proxy mode, state flags, downed/revive.
- `scripts/enemy.gd`: target selection, proxy mode, attack/damage/death events.
- `scripts/hud.gd`: Play Online browser, lobby room, text fields, team panel, downed and revive prompts, online pause/end buttons.
- `server/`: relay and static host, tests and Dockerfile. `docker-compose.yml`, `.env.example`, `Host-Online.cmd`.
- `tools/package-web.sh` / `.ps1`: export plus `build/RelicDiver-Web.zip` (tracked; the server image unpacks it).

## Checks

```sh
cd server && npm test                                   # lobby/relay/static server (5 tests)
tests/net_test.sh /path/to/godot                         # host + guest + late joiner through a real server
xvfb-run godot --path . --script tests/coop_preview.gd   # renders screenshots/coop-*.png
PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs node tests/web_e2e.mjs [shots]   # real browser: menus, invite link, shared dig
```

`net_test.sh` covers identical floors (fingerprints) at B1/B2, guest hits applied by the host, kill/drop replication, per-digger cache choices, part mirroring, downed/revive, gathering at the lift, late-join sync of dead robots and used salvage, and the shared ending. The browser test needs one browser process per player: two Godot tabs in one headless Chromium starve each other under software WebGL.

## Known limits and ideas

- No host migration: if the host leaves, the lobby closes and guests' runs end, with records saved.
- No client-side prediction for robots. Guests see robots about half a round trip late (interpolated at 20 Hz). Warnings still give the same reaction window because windups replay on arrival.
- A web build opened over plain HTTP on a LAN IP can't start (no secure context for `SharedArrayBuffer`). Use `localhost` or the HTTPS domain.
- Trust model: friends-only co-op. The host clamps reported damage, but a modified client could still cheat in its own lobby.
