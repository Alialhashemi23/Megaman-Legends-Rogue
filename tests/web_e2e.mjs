// Browser end-to-end check of the exported web build: a host creates a lobby
// through the real menus, a friend opens the invite link, and both start a dig.
//
//   node tests/web_e2e.mjs [screenshot-dir]
// Needs Playwright (set PLAYWRIGHT_MODULE to its path if it isn't resolvable)
// and an exported build in build/web.
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createServer } from "../server/server.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const shots = path.resolve(process.argv[2] || path.join(here, "..", "build", "e2e"));
fs.mkdirSync(shots, { recursive: true });
const pw = await import(process.env.PLAYWRIGHT_MODULE ? pathToFileURL(process.env.PLAYWRIGHT_MODULE).href : "playwright");
const { chromium } = pw.default || pw;

const app = createServer({ port: 0, webRoot: path.join(here, "..", "build", "web"), log: (m) => console.log("[server] " + m) });
const port = await app.listen();
const base = `http://127.0.0.1:${port}`;
const SCALE = Number(process.env.E2E_SCALE) || 0.5;
const launchArgs = { args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required", "--disable-renderer-backgrounding", "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"] };
// Each digger gets their own browser process, like separate computers.
const browsers = [];
let failed = false;

async function openPage(label, url) {
  const browser = await chromium.launch(launchArgs);
  browsers.push(browser);
  const context = await browser.newContext({ viewport: { width: 1440 * SCALE, height: 900 * SCALE } });
  await context.grantPermissions(["clipboard-read", "clipboard-write"], { origin: base });
  const page = await context.newPage();
  page.logs = [];
  page.on("console", (m) => { page.logs.push(m.text()); if (m.text().startsWith("ONLINE") || /error/i.test(m.text())) console.log(`[${label}] ${m.text()}`); });
  page.on("pageerror", (e) => console.log(`[${label}] pageerror ${e.message}`));
  await page.goto(url);
  return page;
}

async function waitLog(page, pattern, timeout = 60000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (page.logs.some((l) => pattern.test(l))) return true;
    await page.waitForTimeout(250);
  }
  throw new Error(`timed out waiting for ${pattern}`);
}

// HUD coordinates are authored at 1440×900; software WebGL is slow, so the
// test renders smaller and scales clicks to match.
const click = (page, x, y) => page.mouse.click(x * SCALE, y * SCALE);

try {
  const host = await openPage("host", `${base}/`);
  await waitLog(host, /Godot Engine/);
  await host.waitForTimeout(6000);
  await click(host, 300, 498); // Title → Play Online
  await host.waitForTimeout(2000);
  await host.screenshot({ path: path.join(shots, "1-lobby-browser.png") });
  await click(host, 288, 508); // Create Public Lobby
  await waitLog(host, /ONLINE: joined lobby (\w+) as slot 1/);
  const code = host.logs.find((l) => l.startsWith("ONLINE: joined lobby")).split(" ")[3];
  const invite = new URL(host.url());
  if (invite.searchParams.get("lobby") !== code) throw new Error(`address bar should carry the invite (${host.url()})`);
  await click(host, 222, 387); // Copy Invite Link
  await host.waitForTimeout(500);
  const copied = await host.evaluate(() => navigator.clipboard.readText().catch((e) => "ERR " + e.message));
  console.log(`[host] clipboard: ${copied}`);
  if (!copied.endsWith(`/?lobby=${code}`)) throw new Error("invite link should be copied to the clipboard");

  const guest = await openPage("guest", copied);
  await guest.bringToFront();
  await waitLog(guest, new RegExp(`ONLINE: joined lobby ${code} as slot 2`), 60000);
  await guest.waitForTimeout(1500);
  await click(guest, 344, 636); // pick Roll
  await host.waitForTimeout(1500);
  await host.screenshot({ path: path.join(shots, "2-lobby-room-host.png") });
  await guest.screenshot({ path: path.join(shots, "3-lobby-room-guest.png") });

  await click(host, 204, 807); // Start Dig
  await waitLog(host, /ONLINE: dig started .* party=2/);
  await waitLog(guest, /ONLINE: dig started .* party=2/);
  await waitLog(host, /ONLINE: teammate .*slot 2/);
  await waitLog(guest, /ONLINE: teammate .*slot 1/);
  // Walk the guest forward a little so the host sees them move.
  await guest.keyboard.down("KeyW");
  await guest.waitForTimeout(700);
  await guest.keyboard.up("KeyW");
  await host.waitForTimeout(2500);
  await host.screenshot({ path: path.join(shots, "4-dig-host.png"), timeout: 180000 });
  await guest.screenshot({ path: path.join(shots, "5-dig-guest.png"), timeout: 180000 });

  // Mishap 1: the guest reloads the tab. The page asks first, then comes back into the same dig.
  const prompts = [];
  for (const page of [host, guest]) page.on("dialog", (d) => { prompts.push(d.type()); d.accept(); });
  // Let a checkpoint land in browser storage (written to IndexedDB asynchronously).
  await waitLog(guest, /ONLINE: checkpoint saved/, 60000);
  await guest.waitForTimeout(5000);
  const runId = (guest.logs.find((l) => l.includes("dig started")) || "").match(/seed=(\d+)/)[1];
  guest.logs = [];
  await guest.reload();
  await waitLog(guest, /ONLINE: saved dig found .* online=true/, 120000);
  await waitLog(guest, /ONLINE: synced into dig/, 120000);
  if (!prompts.includes("beforeunload")) throw new Error("leaving mid-dig should ask for confirmation");
  console.log(`[guest] back in dig after reload (seed ${runId})`);

  // Mishap 2: the host reloads. Hosting moves to the guest and the host rejoins.
  host.logs = [];
  await host.reload();
  await waitLog(guest, /ONLINE: now hosting/, 120000);
  await waitLog(host, /ONLINE: synced into dig/, 180000);
  console.log("[host] back in dig as a guest; the guest kept it running");
  await guest.screenshot({ path: path.join(shots, "6-after-reloads-guest.png"), timeout: 180000 });
  console.log("WEB_E2E_PASS: menus, lobby, invite link, join, shared dig, guest reload, host reload + migration");
} catch (error) {
  failed = true;
  let n = 0;
  for (const page of browsers.flatMap((b) => b.contexts()).flatMap((c) => c.pages())) {
    console.log(page.url(), "\n  " + page.logs.slice(-15).join("\n  "));
    await page.screenshot({ path: path.join(shots, `failure-${n++}.png`) }).catch(() => {});
  }
  console.log("WEB_E2E_FAIL: " + error.message);
} finally {
  for (const browser of browsers) await browser.close();
  await app.close();
}
process.exit(failed ? 1 : 0);
