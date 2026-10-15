// Owner dashboard tests (roadmap phase 6): access control, MFA, exact counts,
// replay/refresh safety and retention with a fake clock. Needs PostgreSQL like
// accounts.test.js: set TEST_DATABASE_URL. Each run uses its own database.
import { test, before, after, describe } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import pg from "pg";
import { createOTP } from "@better-auth/utils/otp";
import { base32 } from "@better-auth/utils/base32";
import { createServer } from "../server.js";
import { createAccounts } from "../accounts/api.js";
import { createPool, migrate } from "../accounts/db.js";
import { authOptions } from "../accounts/auth.js";
import { createMailer } from "../accounts/mail.js";
import { maskEmail, utcDay } from "../accounts/analytics.js";

const ADMIN_URL = process.env.TEST_DATABASE_URL;
const SECRET = "test-secret-" + "y".repeat(40);
const DAY = 86400000;
let dbName, pool, app, port, base, webRoot, accounts;
let clock = 0;
const mail = [];

describe("owner dashboard", { skip: !ADMIN_URL && "TEST_DATABASE_URL is not set" }, () => {
  before(async () => {
    dbName = `relic_admin_${process.pid}_${Date.now()}`;
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    await admin.query(`create database ${dbName}`);
    await admin.end();
    pool = createPool(ADMIN_URL.replace(/\/[^/]*$/, `/${dbName}`), () => {});
    webRoot = fs.mkdtempSync(path.join(os.tmpdir(), "relic-web-"));
    fs.writeFileSync(path.join(webRoot, "index.html"), "<!doctype html><title>Relic Diver</title>");
    const probe = createServer({ port: 0, webRoot, log: () => {} });
    port = await probe.listen();
    await probe.close();
    base = `http://127.0.0.1:${port}`;
    await migrate(pool, authOptions({ pool, secret: SECRET, origin: base, mailer: createMailer({ sink: [] }) }), () => {});
    accounts = await createAccounts({ pool, secret: SECRET, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 100000, account: 100000 }, now: () => Date.now() + clock, log: process.env.DEBUG_ADMIN ? console.error : () => {} });
    app = createServer({ port, webRoot, log: () => {}, accounts });
    port = await app.listen();
  });

  after(async () => {
    await app?.close();
    await pool?.end();
    fs.rmSync(webRoot, { recursive: true, force: true });
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    await admin.query(`drop database if exists ${dbName} with (force)`);
    await admin.end();
  });

  const cookiesOf = (r, previous = "") => {
    const jar = new Map(previous.split("; ").filter(Boolean).map((c) => [c.split("=")[0], c]));
    for (const c of r.headers.getSetCookie()) {
      const pair = c.split(";")[0];
      if (/max-age=0/i.test(c) || pair.endsWith("=")) jar.delete(pair.split("=")[0]);
      else jar.set(pair.split("=")[0], pair);
    }
    return [...jar.values()].join("; ");
  };

  async function call(pathname, { method, body, cookie, token, origin = base } = {}) {
    const headers = {};
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (origin) headers.Origin = origin;
    if (cookie) headers.Cookie = cookie;
    if (token) headers.Authorization = `Bearer ${token}`;
    const r = await fetch(base + pathname, { method: method || (body !== undefined ? "POST" : "GET"), headers, body: body !== undefined ? JSON.stringify(body) : undefined, redirect: "manual" });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    return { status: r.status, json, headers: r.headers, text };
  }
  const op = () => crypto.randomUUID();

  async function player(name) {
    const email = `${name.toLowerCase()}-${crypto.randomBytes(4).toString("hex")}@example.test`;
    const password = "correct horse battery";
    assert.equal((await call("/api/auth/sign-up/email", { body: { name, email, password } })).status, 200);
    await fetch(mail.findLast((m) => m.to === email && m.kind === "verify").url, { redirect: "manual" });
    const r = await call("/api/auth/sign-in/email", { body: { email, password } });
    assert.equal(r.status, 200, r.text);
    const who = { name, email, password, cookie: cookiesOf(r), token: r.headers.get("set-auth-token") };
    who.id = (await call("/api/v1/profile", { token: who.token })).json.account.id;
    return who;
  }

  const totp = (uri) => createOTP(new TextDecoder().decode(base32.decode(new URL(uri).searchParams.get("secret")))).totp();

  async function makeOwner() {
    const owner = await player("Owner");
    await pool.query(`update "user" set role = 'admin' where id = (select user_id from game_account where id = $1)`, [owner.id]);
    let r = await call("/api/admin/me", { cookie: owner.cookie });
    assert.equal(r.status, 403);
    assert.equal(r.json.error.code, "mfa_setup_required", "admin without an authenticator is turned away");
    r = await call("/api/auth/two-factor/enable", { cookie: owner.cookie, body: { password: owner.password } });
    assert.equal(r.status, 200, r.text);
    owner.uri = r.json.totpURI;
    owner.backup = r.json.backupCodes;
    r = await call("/api/auth/two-factor/verify-totp", { cookie: owner.cookie, body: { code: await totp(owner.uri) } });
    assert.equal(r.status, 200, r.text);
    owner.cookie = cookiesOf(r, owner.cookie);
    return owner;
  }

  test("anonymous visitors, players and game tokens can't read admin data", async () => {
    const page = await call("/admin");
    assert.equal(page.status, 200);
    assert.match(page.headers.get("content-security-policy"), /script-src 'self'/);
    assert.equal((await call("/admin/app.js")).status, 200);
    for (const route of ["/api/admin/me", "/api/admin/stats", "/api/admin/users", "/api/admin/users/acc_x"]) {
      const r = await call(route);
      assert.equal(r.status, 401, route);
      assert.equal(r.json.error.code, "unauthorized");
    }
    const ada = await player("Ada");
    let r = await call("/api/admin/stats", { cookie: ada.cookie });
    assert.equal(r.status, 403);
    assert.equal(r.json.error.code, "forbidden");
    r = await call("/api/admin/users", { token: ada.token });
    assert.equal(r.status, 403, "bearer tokens never reach admin data");
    assert.equal((await call("/api/admin/stats", { method: "POST", cookie: ada.cookie, body: {} })).status, 405);
    assert.equal((await call("/api/admin/nope", { cookie: ada.cookie })).status, 404);
  });

  test("the owner needs the role, an authenticator and a recent check on this session", async () => {
    const owner = await makeOwner();
    let r = await call("/api/admin/me", { cookie: owner.cookie });
    assert.equal(r.status, 200, r.text);
    assert.equal(r.json.email, owner.email);
    r = await call("/api/admin/me", { token: owner.token });
    assert.equal(r.status, 403, "the owner's game token is still refused");

    // A new password sign-in stops at the authenticator.
    r = await call("/api/auth/sign-in/email", { body: { email: owner.email, password: owner.password } });
    assert.equal(r.status, 200);
    assert.equal(r.json.twoFactorRedirect, true);
    let pending = cookiesOf(r);
    assert.equal((await call("/api/admin/me", { cookie: pending })).status, 401, "no session before the code");
    r = await call("/api/auth/two-factor/verify-totp", { cookie: pending, body: { code: "000000" } });
    assert.ok(r.status >= 400, "wrong code refused");
    r = await call("/api/auth/sign-in/email", { body: { email: owner.email, password: owner.password } });
    pending = cookiesOf(r);
    r = await call("/api/auth/two-factor/verify-backup-code", { cookie: pending, body: { code: owner.backup[0] } });
    assert.equal(r.status, 200, r.text);
    const second = cookiesOf(r, pending);
    assert.equal((await call("/api/admin/stats", { cookie: second })).status, 200, "backup code also unlocks the dashboard");

    // The check expires, can be repeated, and sign-out ends access.
    clock = 13 * 60 * 60 * 1000;
    r = await call("/api/admin/me", { cookie: second });
    assert.equal(r.json?.error?.code, "mfa_required");
    r = await call("/api/auth/two-factor/verify-totp", { cookie: second, body: { code: await totp(owner.uri) } });
    assert.equal(r.status, 200, r.text);
    assert.equal((await call("/api/admin/me", { cookie: cookiesOf(r, second) })).status, 200, "step-up check on the same session");
    clock = 0;
    await call("/api/auth/sign-out", { cookie: owner.cookie, body: {} });
    assert.equal((await call("/api/admin/me", { cookie: owner.cookie })).status, 401, "signed-out session loses access");

    // Revoking the role takes effect immediately.
    await pool.query(`update "user" set role = 'player' where email = $1`, [owner.email]);
    assert.equal((await call("/api/admin/me", { cookie: second })).status, 403);
    await pool.query(`update "user" set role = 'admin' where email = $1`, [owner.email]);
  });

  test("distinct users are counted exactly across days and devices; replays and refreshes don't inflate", async () => {
    await pool.query(`truncate analytics_event, activity_day, daily_stat, daily_stat_day`);
    const owner = await makeOwner();
    const [a, b, c] = [await player("Ana"), await player("Ben"), await player("Cid")];
    const today = utcDay(Date.now());
    const at = (days) => { clock = days * DAY; };
    const activity = (who, platform, seconds = 120) => call("/api/v1/activity", { token: who.token, body: { seconds, platform, game_version: 7 } });

    // Day -8: A. Day -2: A on two devices, B. Day 0: A, C (C twice).
    at(-8); assert.equal((await activity(a, "web")).status, 200);
    at(-2); await activity(a, "web"); await activity(a, "android", 3600); await activity(b, "windows");
    at(0); await activity(a, "windows"); await activity(c, "android"); await activity(c, "android");
    assert.equal((await activity(c, "android", 0)).status, 400);

    const run = await call("/api/v1/runs", { token: b.token, body: { op_id: op(), platform: "windows", game_version: 7 } });
    assert.equal(run.status, 201);
    const result = { run_id: run.json.run.id, outcome: { won: true, depth: 3, guardians: 3, scrap: 10, kills: 5, run_time: 600, character: 2 } };
    assert.equal((await call("/api/v1/run-results", { token: b.token, body: result })).status, 200);
    assert.equal((await call("/api/v1/run-results", { token: b.token, body: result })).status, 200, "client retry");

    const stats = (q = "") => call("/api/admin/stats" + q, { cookie: owner.cookie });
    let r = await stats();
    assert.equal(r.status, 200, r.text);
    assert.deepEqual(r.json.active, { dau: 3, wau: 3, mau: 3 }, "today: A, B (via its dig), C");
    const day = (offset) => r.json.days.find((d) => d.day === utcDay(Date.now() + offset * DAY))?.metrics || {};
    assert.equal(day(-8).dau, 1);
    assert.equal(day(-2).dau, 2, "A on two devices counts once");
    assert.equal(day(-2).play_seconds, 120 + 300 + 120, "reports are capped at 300 s each");
    assert.equal(day(0)["runs.started"], 1);
    assert.equal(day(0)["runs.finished"], 1, "replayed result counted once");
    assert.equal(day(0)["runs.wins"], 1);
    assert.equal(day(0)["runs.character.2"], 1);
    assert.equal(day(0)["sync.replays"], 1);
    assert.equal(day(-2).wau, 2);
    assert.equal(day(-2).mau, 2);
    assert.ok(day(0)["login.sign_in.success"] >= 3, "password sign-ins recorded");
    assert.equal(day(0)["login.refresh.success"] || 0, 0, "no refresh has happened yet");

    // A session refresh is recorded separately and is not a sign-in.
    const signIns = day(0)["login.sign_in.success"];
    await pool.query(`update session set "expiresAt" = now() + interval '1 hour' where token = $1`, [a.token.split(".")[0]]);
    assert.equal((await call("/api/v1/profile", { token: a.token })).status, 200);
    r = await stats();
    assert.equal(day(0)["login.sign_in.success"], signIns, "refresh didn't add a sign-in");
    assert.equal(day(0)["login.refresh.success"], 1);

    // A failed password sign-in is a failure, not a login.
    await call("/api/auth/sign-in/email", { body: { email: a.email, password: "wrong password here" } });
    r = await stats();
    assert.equal(day(0)["login.sign_in.failure"], 1);

    r = await stats(`?from=${today}&to=${utcDay(Date.parse(today) - DAY)}`);
    assert.equal(r.status, 400, "reversed range refused");
    r = await stats(`?from=2020-01-01&to=${today}`);
    assert.equal(r.status, 400, "more than 366 days refused");
    r = await stats("?from=2026-02-30");
    assert.equal(r.status, 400, "impossible date refused");
    clock = 0;
  });

  test("player list masks emails; detail shows them only to the owner", async () => {
    const owner = await makeOwner();
    const dee = await player("Dee");
    let r = await call("/api/admin/users?q=" + encodeURIComponent(dee.email), { cookie: owner.cookie });
    assert.equal(r.status, 200);
    assert.equal(r.json.total, 1);
    assert.equal(r.json.users[0].email, maskEmail(dee.email));
    assert.ok(!JSON.stringify(r.json).includes(dee.email), "no full email in the list");
    r = await call("/api/admin/users?q=De", { cookie: owner.cookie });
    assert.ok(r.json.users.some((u) => u.id === dee.id), "name search");
    r = await call("/api/admin/users?page=1", { cookie: owner.cookie });
    assert.ok(r.json.total >= 2 && r.json.users.length <= r.json.page_size);
    r = await call("/api/admin/users/" + dee.id, { cookie: owner.cookie });
    assert.equal(r.status, 200);
    assert.equal(r.json.email, dee.email);
    for (const secret of ["password", "token", "secret", "backupCodes"]) assert.ok(!(secret in r.json), secret);
    assert.ok(!JSON.stringify(r.json).includes(dee.token), "no session tokens");
    assert.equal((await call("/api/admin/users/acc_missing", { cookie: owner.cookie })).status, 404);
  });

  test("retention keeps summaries and reward deduplication; deleting a user removes their analytics", async () => {
    const owner = await makeOwner();
    const eve = await player("Eve");
    const run = await call("/api/v1/runs", { token: eve.token, body: { op_id: op(), platform: "web", game_version: 7 } });
    const result = { run_id: run.json.run.id, outcome: { won: false, depth: 1, guardians: 0, scrap: 3, kills: 2, run_time: 60, character: 0 } };
    const first = await call("/api/v1/run-results", { token: eve.token, body: result });
    assert.equal(first.status, 200);
    const today = utcDay(Date.now());

    clock = 40 * DAY;
    await accounts.analytics.prune();
    const events = Number((await pool.query(`select count(*) n from analytics_event where at < $1`, [today + "T23:59:59Z"])).rows[0].n);
    assert.equal(events, 0, "events older than 30 days are deleted");
    const kept = (await pool.query(`select value from daily_stat where day = $1 and metric = 'runs.finished'`, [today])).rows[0];
    assert.ok(Number(kept?.value) >= 1, "the daily summary survives");
    assert.equal(Number((await pool.query(`select count(*) n from operation where account_id = $1`, [eve.id])).rows[0].n) >= 1, true, "deduplication ledger untouched");
    clock = 0;
    const again = await call("/api/v1/run-results", { token: eve.token, body: result });
    assert.equal(again.status, 200);
    assert.deepEqual(again.json, first.json, "an old retry still replays instead of paying twice");

    clock = 100 * DAY;
    await accounts.analytics.prune();
    assert.equal(Number((await pool.query(`select count(*) n from activity_day where day <= $1`, [today])).rows[0].n), 0, "activity days older than 90 days are deleted");
    clock = 400 * DAY;
    await accounts.analytics.prune();
    assert.equal(Number((await pool.query(`select count(*) n from daily_stat where day <= $1`, [today])).rows[0].n), 0, "aggregates older than 12 months are deleted");
    clock = 0;

    await call("/api/v1/activity", { token: eve.token, body: { seconds: 30, platform: "web" } });
    const userId = (await pool.query(`select user_id from game_account where id = $1`, [eve.id])).rows[0].user_id;
    await pool.query(`delete from "user" where id = $1`, [userId]);
    const left = (await pool.query(`select (select count(*) from analytics_event where account_id = $1 or user_id = $2) e, (select count(*) from activity_day where account_id = $1) a`, [eve.id, userId])).rows[0];
    assert.deepEqual([Number(left.e), Number(left.a)], [0, 0]);
    assert.equal((await call("/api/v1/profile", { token: eve.token })).status, 401, "a deleted account's queued retries can't recreate it");
    assert.equal((await call("/api/admin/users/" + eve.id, { cookie: owner.cookie })).status, 404);
  });

  test("live counts come from the relay", async () => {
    const owner = await makeOwner();
    const { WebSocket } = await import("ws");
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    await new Promise((resolve) => ws.on("open", resolve));
    ws.send(JSON.stringify({ t: "hello", name: "Guest", id: "guest-1", v: 7 }));
    await new Promise((resolve) => ws.on("message", resolve));
    const r = await call("/api/admin/stats", { cookie: owner.cookie });
    assert.equal(r.json.live.connections, 1);
    assert.equal(r.json.live.guest_connections, 1);
    assert.equal(r.json.live.accounts, 0);
    ws.close();
  });
});
