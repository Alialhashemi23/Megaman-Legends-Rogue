# Hosting Relic Diver online

> **This project's deployment:** `https://megaman.galosengen.dev`, hosted from the user's PC through a Cloudflare Tunnel (domain `galosengen.dev` on Cloudflare). The Windows build connects there by default (`relic_diver/online/default_server` in project.godot).

Relic Diver runs in the browser and supports online co-op for up to four diggers. One small server does everything: it serves the game files and runs the lobby service that connects players. Publish that server on your domain with a **Cloudflare Tunnel**. It needs no port forwarding, exposes no home IP address and handles HTTPS certificates for you.

```
friend's browser ──HTTPS/WSS──▶ Cloudflare ──tunnel──▶ cloudflared ──▶ relic-diver server (:8080)
                                                         (on one of your PCs)
```

Players open `https://your-domain/`, choose **Play Online** and either create a lobby or pick one from the lobby browser. **Copy Invite Link** gives a link like `https://your-domain/?lobby=K7QX2`; opening it drops a friend straight into your lobby. The short form `https://your-domain/j/K7QX2` works too.

## What you need

- A domain using Cloudflare DNS (the domain's nameservers point at Cloudflare). A free plan is fine.
- One always-on computer for the server. Windows, macOS or Linux all work.
- Either **Docker** (Docker Desktop on Windows/macOS), or **Node.js 20+** plus `cloudflared`.

## 1. Create the tunnel (once)

1. In the Cloudflare dashboard open **Networking → Tunnels** (older dashboards: **Zero Trust → Networks → Tunnels**) and choose **Create a tunnel**. Pick **Cloudflared** if asked, and name the tunnel e.g. `relic-diver`.
2. On the install screen choose **Docker** (or **Windows** if you skip Docker). Don't run the shown command; copy only the long **token** after `--token`. Keep it private: it works like a password for your tunnel.
3. Open the tunnel's **Routes** tab → **Add route** → **Published application** (older dashboards: **Public hostname**):
   - **Domain**: your domain. Leave the subdomain empty for `your-domain`, or use e.g. `play` for `play.your-domain`.
   - **Service URL**: `http://relic-diver:8080` with Docker (option A), or `http://localhost:8080` without Docker (option B).
4. Save. Cloudflare creates the DNS record automatically.

WebSockets are on by default. Leave **Rocket Loader** off for this hostname, since the game needs its scripts untouched. If friends get stuck on a challenge page, turn off **Bot Fight Mode** for the domain.

## 2A. Run with Docker (recommended)

From the repository folder:

```sh
cp .env.example .env          # Windows: copy .env.example .env
# edit .env and paste:  TUNNEL_TOKEN=<your token>
docker compose up -d --build
```

That starts two containers: `relic-diver` (game + lobbies, also at http://localhost:8080 on that PC) and `cloudflared` (the tunnel). Both restart automatically after reboots. Check them with `docker compose ps` and `docker compose logs -f`.

## 2B. Run without Docker (Windows)

1. Install Node.js LTS from https://nodejs.org/ and cloudflared with `winget install --id Cloudflare.cloudflared`.
2. Install the tunnel as a Windows service (runs at startup): `cloudflared service install <your token>`. Its public hostname must point at `localhost:8080`.
3. Double-click **Host-Online.cmd** in the repository folder. It unpacks the web build, installs the server's one dependency and starts the server. Keep that window open while people play.

On macOS/Linux the equivalent is `cd server && npm ci --omit=dev`, unzip `build/RelicDiver-Web.zip` into `build/web/`, run `node server/server.js`, and run the tunnel with `cloudflared tunnel run --token <your token>`.

## 3. Play

Open `https://your-domain/`. The first visit downloads about 13 MB (the server compresses the game). After that the browser revalidates instead of downloading it again. Use a desktop browser with keyboard and mouse: Chrome, Edge, Firefox or Safari.

- **Create Public Lobby** lists your lobby in everyone's lobby browser. **Create Private Lobby** hides it, so only people with the link or the 5-letter code can join.
- Everyone picks a digger (Mega, Roll, Tron or Servbot, each with a signature attack), then presses **Ready**, including the host. Duplicate diggers are welcome. The host's **Start Dig** becomes available once the whole party is Ready.
- Start opens a three-second countdown. **Unready / Cancel**, **Cancel launch**, or **Esc / B** cancels before launch; changing the party or its loadout resets consent. **Change loadout** waits for cancellation/unready confirmation before opening the Workshop.
- After countdown, **Preparing dig** names anyone still loading or confirming their account. Gameplay begins once everyone has prepared. Account errors offer Retry/Take over; they never silently switch an account to Guest. Canceling preparation preserves an older saved dig.
- Friends can join a dig already underway. They arrive at the current descent with a fresh build.
- In the dig, click once to capture the mouse for aiming. Browsers only allow mouse capture after a click.

The Windows build can join the same lobbies. It defaults to `wss://megaman.galosengen.dev/ws`; to use another server, change **Play Online → Dig Server**.

## How co-op plays

- Everyone shares one run: the same seeded ruins, the same robots, shared **scrap** and shared **XP** (each digger levels up and picks their own upgrade).
- Builds are personal. Every **part cache** gives *each* digger their own pick, and each guardian drops one core per digger. Cache, level and guardian-milestone choices wait until you open them with **Tab** (controller **Select**). Pick sequentially with a fresh press for each offer. **Tab / Select** or **Esc / B** puts unused choices aside without changing their options; exact waiting offers survive rejoining. Unpicked upgrades expire at final extraction.
- The ruins map is shared: rooms any teammate explores show up for everyone, with part caches marked (gold ready, flashing cyan waiting for you, dark opened).
- Robots gain Life, and rooms gain extra robots, for each digger in the party. Guardians scale the most.
- At 0 Life a digger goes **down**. Any teammate standing next to them for about 2.5 seconds revives them with 35% Life. The dig ends only when everyone is down. Taking the lift also revives downed diggers.
- The lift waits until every standing digger is aboard.
- Menus and upgrade choices don't pause the dig online. Your digger stands still while choosing, and hits can still land, so find a safe spot before opening your waiting upgrades. Going down closes the overlay and keeps unused offers for after a revive.
- Controllers work everywhere (see Options → Controls & bindings to remap). In a dig: LB pings and the D-pad sends callouts.
- Talk with **T** (or Enter), mark a spot, robot, cache or lift for the team with **G** (or middle mouse), and shout quick callouts with **1–4** (*Help!*, *Over here!*, *Nice!*, *Wait up!*). Chat also works in the lobby room.
- While you're down, the camera follows a standing teammate. Click to switch who you watch.
- The host can **Remove** a player (they can't rejoin that lobby), **Lock** the lobby so only people already in it can come back, or set a **password** when creating it. Password lobbies show a lock in the browser, and the invite link carries the password.

Records, unlocks and settings are saved per browser (or per PC for the Windows build). Each player keeps their own unlock progress.

## Your run is safe

A dig survives the usual accidents:

| What happens | What the game does |
|---|---|
| Someone refreshes or closes the tab | The browser asks first. If they leave anyway, opening the link again (or **Rejoin Dig** on the title) puts them back in the same dig with their exact build: parts, level, Life, even a part choice they hadn't finished. |
| The host leaves or crashes | Hosting moves to another player within a moment and the dig carries on. The old host can rejoin as a regular player with their build. |
| Wi-Fi drops briefly | The dig freezes for that player with a *Reconnecting…* banner, then they're back automatically (it keeps trying for 90 seconds). |
| Everyone drops out | The server keeps the lobby and the host's latest checkpoint for 15 minutes (`RUN_GRACE_MINUTES`). The first player back resumes the dig and everyone else rejoins with the same link. |
| The server restarts | Each browser keeps its own copy of the dig. **Rejoin Dig** recreates the lobby under the same code and restores it, and friends rejoin with the same link. |
| Someone wants to stop playing | **Leave Dig** in the pause menu (second click confirms). The others keep going; a leaving host hands hosting to the next player. The host can also **End Dig for Everyone**. |

The game saves every 5 seconds and immediately whenever a build changes, so at most a few seconds of robot fighting are ever lost. Starting a new dig over a saved one asks for confirmation, and the abandoned dig's machines still count toward unlocks. Leaving a lobby, ending a dig for everyone and removing players all need a second click.

Everyone in a lobby must run the same game version. After you update the server, players with an old tab open are asked to refresh.

## Player accounts (optional)

The server can also offer accounts so progress follows players between browsers, PCs and the Android build. It's off by default and needs a database, a mail provider and backups; see [ACCOUNTS-OPS.md](ACCOUNTS-OPS.md). The game itself starts using accounts in a later update.

## Updating the game

After changing gameplay, re-export the web build and restart the server:

```sh
tools/package-web.sh /path/to/godot      # Windows: tools\package-web.ps1
docker compose up -d --build             # or restart Host-Online.cmd
```

The export needs Godot 4.7.1 with its **Web** export templates (Editor → Manage Export Templates). Commit the refreshed `build/RelicDiver-Web.zip` so other machines can rebuild the server image without Godot.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Page loads but stays on a blank or blue screen | The game needs cross-origin isolation headers. Serve it through `server/server.js`, not another static host. Open it via `https://your-domain` or `http://localhost:8080`, never a LAN IP over plain HTTP: browsers disable the needed features there. |
| "Could not reach the dig server" | The tunnel or server is down. Check `docker compose ps` or the Host-Online window. In Cloudflare, the tunnel must show **Healthy**. |
| A link says the lobby no longer exists | Everyone left more than 15 minutes ago (or the server restarted and nobody has rejoined yet). Whoever has the dig saved can choose **Rejoin Dig** to bring it back under the same code. |
| "Different version of the game" | The server was updated. Refresh the page. |
| Lag or rubber-banding | Every packet goes through the server PC. Use a wired connection for it if possible, and the host should have a decent connection too, since the host's browser runs the robots. |
| Joined but can't aim | Click inside the game once to capture the mouse. |

## Security notes

- `.env` holds your tunnel token and is ignored by Git. Never commit or share it. If it leaks, delete the tunnel in Cloudflare and create a new one.
- The server only exposes the game files, `/ws`, `/healthz` and `/api/lobbies` (public lobby list). It stores nothing on disk and keeps lobbies in memory.
- Lobby names and player names are limited to 28/16 characters with control characters stripped. Packet rates and sizes are capped per connection.
- This is a non-commercial fan project that includes Capcom character models. See LICENSE.md and the character credits, which are also served at `/LICENSE.md` and `/CHARACTER-CREDITS.md`. Keep the site non-commercial.

Build 36 uses game protocol 13. Results keep the same lobby code; choose Return to Lobby, then Ready again for another dig. Protocol-12 Android 0.21.0 needs a matching client update.
