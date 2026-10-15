// Renders the owner dashboard with disposable fixture data (not part of npm test).
//   TEST_DATABASE_URL=postgres://… PLAYWRIGHT_MODULE=/path/to/playwright-core/index.mjs \
//   [BROWSER_PATH=…/msedge.exe] node test/admin-preview.mjs [out-dir]
// Creates and drops its own database; screenshots go to ../screenshots by default.
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import pg from "pg";
import { createOTP } from "@better-auth/utils/otp";
import { base32 } from "@better-auth/utils/base32";
import { createServer } from "../server.js";
import { createAccounts } from "../accounts/api.js";
import { createPool, migrate } from "../accounts/db.js";
import { authOptions } from "../accounts/auth.js";
import { createMailer } from "../accounts/mail.js";

const ADMIN_URL = process.env.TEST_DATABASE_URL;
if (!ADMIN_URL || !process.env.PLAYWRIGHT_MODULE) throw new Error("Set TEST_DATABASE_URL and PLAYWRIGHT_MODULE.");
const out = path.resolve(process.argv[2] || path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "screenshots"));
const SECRET = "preview-secret-" + "z".repeat(40);
const DAY = 86400000;
const mail = [];
let clock = 0;

const dbName = `relic_preview_${process.pid}`;
const admin = new pg.Client({ connectionString: ADMIN_URL });
await admin.connect();
await admin.query(`create database ${dbName}`);
await admin.end();
const pool = createPool(ADMIN_URL.replace(/\/[^/]*$/, `/${dbName}`), () => {});
const webRoot = fs.mkdtempSync(path.join(os.tmpdir(), "relic-web-"));
fs.writeFileSync(path.join(webRoot, "index.html"), "<!doctype html><title>Relic Diver</title>");
const probe = createServer({ port: 0, webRoot, log: () => {} });
let port = await probe.listen();
await probe.close();
const base = `http://127.0.0.1:${port}`;
let app, browser;
try {
  await migrate(pool, authOptions({ pool, secret: SECRET, origin: base, mailer: createMailer({ sink: [] }) }), () => {});
  const accounts = await createAccounts({ pool, secret: SECRET, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 1e6, account: 1e6 }, now: () => Date.now() + clock, log: () => {} });
  app = createServer({ port, webRoot, log: () => {}, accounts });
  port = await app.listen();

  const call = async (p, { body, token, cookie } = {}) => {
    const headers = { Origin: base };
    if (body) headers["Content-Type"] = "application/json";
    if (token) headers.Authorization = `Bearer ${token}`;
    if (cookie) headers.Cookie = cookie;
    const r = await fetch(base + p, { method: body ? "POST" : "GET", headers, body: body && JSON.stringify(body), redirect: "manual" });
    return { r, json: await r.json().catch(() => null) };
  };
  const jar = (r, prev = "") => {
    const m = new Map(prev.split("; ").filter(Boolean).map((c) => [c.split("=")[0], c]));
    for (const c of r.headers.getSetCookie()) m.set(c.split(";")[0].split("=")[0], c.split(";")[0]);
    return [...m.values()].join("; ");
  };
  async function player(name) {
    const email = `${name.toLowerCase()}@example.test`;
    await call("/api/auth/sign-up/email", { body: { name, email, password: "correct horse battery" } });
    await fetch(mail.findLast((m) => m.to === email).url, { redirect: "manual" });
    const { r } = await call("/api/auth/sign-in/email", { body: { email, password: "correct horse battery" } });
    return { email, token: r.headers.get("set-auth-token"), cookie: jar(r) };
  }

  const owner = await player("Owner");
  await pool.query(`update "user" set role = 'admin' where email = $1`, [owner.email]);
  const enabled = await call("/api/auth/two-factor/enable", { cookie: owner.cookie, body: { password: "correct horse battery" } });
  const secret = new TextDecoder().decode(base32.decode(new URL(enabled.json.totpURI).searchParams.get("secret")));
  const verified = await call("/api/auth/two-factor/verify-totp", { cookie: owner.cookie, body: { code: await createOTP(secret).totp() } });
  owner.cookie = jar(verified.r, owner.cookie);

  const names = ["Volnutt", "Roll", "Tron", "Data", "Barrell", "Teisel", "Bon", "Joe"];
  const players = [];
  for (const n of names) players.push(await player(n));
  const platforms = ["web", "windows", "android"];
  for (let d = -27; d <= 0; d++) {
    clock = d * DAY;
    for (const [i, p] of players.entries()) {
      if ((i + d + 30) % 3 === 0 || (i < 2 && d > -10)) continue;
      const platform = platforms[(i + d + 30) % 3];
      await call("/api/v1/activity", { token: p.token, body: { seconds: 300, platform } });
      if ((i + d) % 2 === 0) {
        const won = (i + d + 32) % 4 === 0, depth = 1 + (i + 3 - d) % 3, character = (i * 3 + 30 + d) % 4;
        const run = await call("/api/v1/runs", { token: p.token, body: { op_id: crypto.randomUUID(), platform, game_version: 7 } });
        await call("/api/v1/run-results", { token: p.token, body: { run_id: run.json.run.id, outcome: won ? { won, depth: 3, guardians: 3, scrap: 40, kills: 30, run_time: 900, character } : { won, depth, guardians: depth - 1, scrap: 20, kills: 12, run_time: 700, character } } });
      }
    }
  }
  clock = 0;

  const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
  browser = await chromium.launch(process.env.BROWSER_PATH ? { executablePath: process.env.BROWSER_PATH } : {});
  fs.mkdirSync(out, { recursive: true });
  const cookies = (c) => c.split("; ").map((pair) => ({ name: pair.split("=")[0], value: pair.slice(pair.indexOf("=") + 1), url: base }));

  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.context().addCookies(cookies(owner.cookie));
  await page.goto(base + "/admin");
  await page.waitForSelector(".chart svg");
  await page.waitForSelector("tr.pick");
  await page.screenshot({ path: path.join(out, "admin-dashboard.png"), fullPage: true });
  await page.click("tr.pick");
  await page.waitForSelector("#who");
  await page.locator("#users").screenshot({ path: path.join(out, "admin-player.png") });

  const narrow = await browser.newPage({ viewport: { width: 420, height: 860 } });
  await narrow.context().addCookies(cookies(owner.cookie));
  await narrow.goto(base + "/admin");
  await narrow.waitForSelector(".chart svg");
  await narrow.screenshot({ path: path.join(out, "admin-dashboard-narrow.png") });

  // A fresh browser session must pass the authenticator before seeing anything.
  const fresh = await browser.newPage({ viewport: { width: 900, height: 700 } });
  await fresh.goto(base + "/account?return=%2Fadmin");
  await fresh.fill("#e", owner.email);
  await fresh.fill("#p", "correct horse battery");
  await fresh.click("form button");
  await fresh.waitForSelector("text=Authenticator code");
  await fresh.screenshot({ path: path.join(out, "admin-signin-code.png") });
  await fresh.fill("#c", await createOTP(secret).totp());
  await fresh.click("form button");
  await fresh.waitForSelector("text=Owner dashboard");
  await fresh.goto(base + "/admin");
  await fresh.waitForSelector(".chart svg");
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  console.log(`Screenshots written to ${out}${errors.length ? "; page errors: " + errors.join(" | ") : ""}`);
} finally {
  await browser?.close();
  await app?.close();
  await pool.end();
  fs.rmSync(webRoot, { recursive: true, force: true });
  const cleanup = new pg.Client({ connectionString: ADMIN_URL });
  await cleanup.connect();
  await cleanup.query(`drop database if exists ${dbName} with (force)`);
  await cleanup.end();
}
