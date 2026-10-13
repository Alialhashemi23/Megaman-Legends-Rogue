# Hosting Relic Diver online

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

1. In the Cloudflare dashboard open **Zero Trust → Networks → Tunnels** and choose **Create a tunnel**. Pick **Cloudflared** and give the tunnel a name such as `relic-diver`.
2. Cloudflare shows install commands containing a long **token**, the text after `--token` or `service install`. Copy it and keep it private. It works like a password for your tunnel.
3. Add a **public hostname** (newer dashboards call these *published application routes*):
   - **Domain**: your domain. Leave the subdomain empty for `your-domain`, or use e.g. `play` for `play.your-domain`.
   - **Service type**: `HTTP`
   - **URL**: `relic-diver:8080` if you use Docker (option A), or `localhost:8080` without Docker (option B).
4. Save. Cloudflare creates the DNS record automatically.

WebSockets are enabled by default on Cloudflare. Leave **Rocket Loader** off for this hostname. The game needs its scripts untouched.

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
- Everyone picks Mega or Roll and a buster in the lobby. Only the host can start the dig.
- Friends can join a dig already underway. They arrive at the current descent with a fresh build.
- In the dig, click once to capture the mouse for aiming. Browsers only allow mouse capture after a click.

The Windows build can join the same lobbies: **Play Online → Dig Server**, enter `wss://your-domain/ws`.

## How co-op plays

- Everyone shares one run: the same seeded ruins, the same robots, shared **scrap** and shared **XP** (each digger levels up and picks their own upgrade).
- Builds are personal. Every **part cache** gives *each* digger their own pick, and each guardian drops one core per digger.
- Robots gain Life, and rooms gain extra robots, for each digger in the party. Guardians scale the most.
- At 0 Life a digger goes **down**. Any teammate standing next to them for about 2.5 seconds revives them with 35% Life. The dig ends only when everyone is down. Taking the lift also revives downed diggers.
- The lift waits until every standing digger is aboard.
- Menus and part choices don't pause the dig online. While you choose a part you're protected and robots look for other targets.
- If the host leaves, the lobby closes and everyone's dig ends with its record saved. Guests can come and go freely.

Records, unlocks and settings are saved per browser (or per PC for the Windows build). Each player keeps their own unlock progress.

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
| A link says the lobby no longer exists | The host closed the lobby or left. Lobbies only live while their host is connected. |
| Lag or rubber-banding | Every packet goes through the server PC. Use a wired connection for it if possible, and the host should have a decent connection too, since the host's browser runs the robots. |
| Joined but can't aim | Click inside the game once to capture the mouse. |

## Security notes

- `.env` holds your tunnel token and is ignored by Git. Never commit or share it. If it leaks, delete the tunnel in Cloudflare and create a new one.
- The server only exposes the game files, `/ws`, `/healthz` and `/api/lobbies` (public lobby list). It stores nothing on disk and keeps lobbies in memory.
- Lobby names and player names are limited to 28/16 characters with control characters stripped. Packet rates and sizes are capped per connection.
- This is a non-commercial fan project that includes Capcom character models. See LICENSE.md and the character credits, which are also served at `/LICENSE.md` and `/CHARACTER-CREDITS.md`. Keep the site non-commercial.
