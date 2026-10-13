# Project instructions

Read HANDOFF.md for current status and DESIGN.md for game direction. Read only the relevant subsystem handoff in docs/handoff/ before changing that area. Do not rescan backups, dump all scripts, repeat completed work or rerun every suite to establish context.

Preserve the original Mega Man Legends PS1 look: supplied character models, painted textures, responsive compact motion, steady buster aiming, colorful mysterious ruins, cobalt adventure menus and original music. Keep run power reset with persistent item/weapon unlocks. Respect the user's latest task and preserve personal saves.

The user authorized this GitHub repository: https://github.com/Alialhashemi23/Megaman-Legends-Rogue. Earlier local-only instructions were superseded for that destination. Do not deploy, monetize, create releases or publish elsewhere without a request. Never commit saves, secrets, import caches, backups, raw captures or loose engine executables. Keep asset/license exceptions intact.

The user later requested browser co-op hosted on their own domain via Cloudflare Tunnel; the repo ships the server and deployment files and the user deploys. Never commit .env or tunnel tokens. Keep build/RelicDiver-Web.zip matching shipped gameplay (tools/package-web.ps1 or .sh). See docs/handoff/NETWORK.md and docs/ONLINE.md.

Work autonomously within the requested scope. Do not spawn subagents unless the user asks. Use relevant checks after meaningful changes, and keep technical handoffs current. The playable pack and portable ZIP must match shipped gameplay changes. Use tools/package-windows.ps1 to refresh the ZIP after exporting and updating build notices.
