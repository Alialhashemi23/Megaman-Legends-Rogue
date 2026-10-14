// Account API contract tests (docs/ACCOUNT-API.md). They need a PostgreSQL
// server: set TEST_DATABASE_URL to an admin connection, e.g.
//   docker run -d --name relic-test-pg -e POSTGRES_PASSWORD=test -p 127.0.0.1:55432:5432 postgres:17-alpine
//   TEST_DATABASE_URL=postgres://postgres:test@127.0.0.1:55432/postgres npm test
// Each run creates and drops its own database. Without the variable they are skipped.
import { test, before, after, describe } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import pg from "pg";
import { WebSocket } from "ws";
import { createServer } from "../server.js";
import { createAccounts } from "../accounts/api.js";
import { createPool, migrate } from "../accounts/db.js";
import { authOptions } from "../accounts/auth.js";
import { createMailer } from "../accounts/mail.js";

const ADMIN_URL = process.env.TEST_DATABASE_URL;
const SECRET = "test-secret-" + "x".repeat(40);
const ORIGIN = "http://127.0.0.1";
let dbName, dbUrl, pool, app, port, base, webRoot, accounts;
let clockOffset = 0;
const mail = [];

async function startApp() {
  accounts = await createAccounts({ pool, secret: SECRET, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 100000, account: 100000 }, now: () => Date.now() + clockOffset, log: () => {} });
  app = createServer({ port, webRoot, log: () => {}, accounts });
  port = await app.listen();
}

describe("accounts", { skip: !ADMIN_URL && "TEST_DATABASE_URL is not set" }, () => {
  before(async () => {
    dbName = `relic_test_${process.pid}_${Date.now()}`;
    const admin = new pg.Client({ connectionString: ADMIN_URL });
    await admin.connect();
    await admin.query(`create database ${dbName}`);
    await admin.end();
    dbUrl = ADMIN_URL.replace(/\/[^/]*$/, `/${dbName}`);
    pool = createPool(dbUrl, () => {});
    webRoot = fs.mkdtempSync(path.join(os.tmpdir(), "relic-web-"));
    fs.writeFileSync(path.join(webRoot, "index.html"), "<!doctype html><title>Relic Diver</title>");
    // The origin must be known before the auth schema/options exist, so pick the port first.
    const probe = createServer({ port: 0, webRoot, log: () => {} });
    port = await probe.listen();
    await probe.close();
    base = `${ORIGIN}:${port}`;
    await migrate(pool, authOptions({ pool, secret: SECRET, origin: base, mailer: createMailer({ sink: [] }) }), () => {});
    await startApp();
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

  async function call(pathname, { method, body, cookie, token, origin = base, raw } = {}) {
    const headers = {};
    if (body !== undefined) headers["Content-Type"] = "application/json";
    if (origin) headers.Origin = origin;
    if (cookie) headers.Cookie = cookie;
    if (token) headers.Authorization = `Bearer ${token}`;
    const r = await fetch(base + pathname, { method: method || (body !== undefined ? "POST" : "GET"), headers, body: raw ?? (body !== undefined ? JSON.stringify(body) : undefined), redirect: "manual" });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch {}
    return { status: r.status, json, headers: r.headers, text };
  }
  const op = () => crypto.randomUUID();

  // A verified player with a cookie session and a bearer token.
  async function player(name, extra = {}) {
    const email = `${name.toLowerCase()}-${crypto.randomBytes(4).toString("hex")}@example.test`;
    const password = "correct horse battery";
    let r = await call("/api/auth/sign-up/email", { body: { name, email, password, ...extra } });
    assert.equal(r.status, 200, `sign-up ${r.text}`);
    const link = mail.findLast((m) => m.to === email && m.kind === "verify");
    assert.ok(link, "verification mail sent");
    r = await fetch(link.url, { redirect: "manual" });
    assert.ok(r.status < 400, "verification link works");
    r = await call("/api/auth/sign-in/email", { body: { email, password } });
    assert.equal(r.status, 200, `sign-in ${r.text}`);
    const cookie = r.headers.getSetCookie().map((c) => c.split(";")[0]).join("; ");
    const token = r.headers.get("set-auth-token");
    assert.ok(cookie.includes("session_token") && token);
    const profile = await call("/api/v1/profile", { token });
    return { name, email, password, cookie, token, id: profile.json.account.id };
  }

  async function startRun(who, extra = {}) {
    return call("/api/v1/runs", { token: who.token, body: { op_id: op(), platform: "windows", game_version: 7, ...extra } });
  }
  const outcome = (extra = {}) => ({ won: false, depth: 2, guardians: 1, scrap: 37, kills: 41, run_time: 655.2, character: 1, ...extra });

  test("guests and unverified users get clear errors", async () => {
    let r = await call("/api/v1/profile");
    assert.equal(r.status, 401);
    assert.equal(r.json.error.code, "unauthorized");
    assert.match(r.json.error.request_id, /^req_/);
    const email = `unverified-${Date.now()}@example.test`;
    await call("/api/auth/sign-up/email", { body: { name: "Late", email, password: "correct horse battery" } });
    r = await call("/api/auth/sign-in/email", { body: { email, password: "correct horse battery" } });
    assert.equal(r.status, 403, "no session until the email is confirmed");
    assert.equal(r.json.code, "EMAIL_NOT_VERIFIED");
    r = await call("/api/v1/nope");
    assert.equal(r.status, 404);
    r = await call("/api/v1/profile", { method: "DELETE", token: "x" });
    assert.equal(r.status, 405);
  });

  test("a new account starts empty and nobody can grant themselves admin", async () => {
    const a = await player("Ada", { role: "admin" });
    const r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.status, 200);
    assert.match(r.json.account.id, /^acc_/);
    assert.equal(r.json.account.role, "player", "role in the sign-up body is ignored");
    assert.equal(r.json.revision, 0);
    assert.deepEqual([r.json.profile.zenny, r.json.profile.runs, r.json.active_run], [0, 0, null]);
    const same = await call("/api/v1/profile", { cookie: a.cookie });
    assert.equal(same.json.account.id, a.id, "cookie and bearer are the same account");
    const update = await call("/api/auth/update-user", { cookie: a.cookie, body: { role: "admin" } });
    const after = await call("/api/v1/profile", { token: a.token });
    assert.equal(after.json.account.role, "player", `update-user can't set the role (${update.status})`);
  });

  test("cookie writes need the game's own origin", async () => {
    const a = await player("Bea");
    let r = await call("/api/v1/lobby-ticket", { cookie: a.cookie, body: {}, origin: "https://evil.example" });
    assert.equal(r.status, 403);
    assert.equal(r.json.error.code, "forbidden");
    r = await call("/api/v1/lobby-ticket", { cookie: a.cookie, body: {}, origin: null });
    assert.equal(r.status, 403, "no Origin header at all");
    r = await call("/api/v1/lobby-ticket", { cookie: a.cookie, body: {} });
    assert.equal(r.status, 200);
    r = await call("/api/v1/lobby-ticket", { token: a.token, body: {}, origin: null });
    assert.equal(r.status, 200, "bearer requests aren't ambient, so no origin is needed");
  });

  test("bodies are validated", async () => {
    const a = await player("Cy");
    let r = await call("/api/v1/purchases", { token: a.token, raw: "{not json", method: "POST" });
    assert.equal(r.status, 400);
    r = await call("/api/v1/discoveries", { token: a.token, raw: JSON.stringify({ op_id: op(), parts: ["lens"], pad: "x".repeat(20000) }), method: "POST" });
    assert.equal(r.status, 413);
    r = await call("/api/v1/discoveries", { token: a.token, body: { op_id: "short", parts: ["lens"] } });
    assert.equal(r.json.error.code, "validation");
    r = await startRun(a, { platform: "ps1" });
    assert.equal(r.status, 400);
  });

  test("one active run per account, with explicit takeover", async () => {
    const a = await player("Dee");
    const first = await startRun(a);
    assert.equal(first.status, 201);
    const runA = first.json.run.id;
    let r = await startRun(a, { platform: "web" });
    assert.equal(r.status, 409);
    assert.equal(r.json.error.code, "active_run");
    assert.equal(r.json.active_run.id, runA);
    r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.json.active_run.id, runA);
    const second = await startRun(a, { platform: "web", takeover: true });
    assert.equal(second.status, 201, "takeover starts a new run");
    r = await call(`/api/v1/runs/${runA}/heartbeat`, { token: a.token, body: {} });
    assert.equal(r.status, 409, "the old device learns it was taken over");
    r = await call(`/api/v1/runs/${second.json.run.id}/heartbeat`, { token: a.token, body: {} });
    assert.equal(r.status, 200);
    // The superseded run can still report its result (a lost lease never discards one).
    r = await call("/api/v1/run-results", { token: a.token, body: { run_id: runA, outcome: outcome() } });
    assert.equal(r.status, 200);
    assert.equal(r.json.result.zenny, 117);
    // Another account can't see or touch these runs.
    const b = await player("Eve");
    r = await call(`/api/v1/runs/${second.json.run.id}/heartbeat`, { token: b.token, body: {} });
    assert.equal(r.status, 404);
    r = await call("/api/v1/run-results", { token: b.token, body: { run_id: second.json.run.id, outcome: outcome() } });
    assert.equal(r.status, 404);
    r = await call("/api/v1/profile", { token: b.token });
    assert.equal(r.json.profile.zenny, 0);
  });

  test("an expired lease frees the account without losing the result", async () => {
    const a = await player("Fay");
    const run = (await startRun(a)).json.run.id;
    clockOffset += 11 * 60 * 1000;
    const next = await startRun(a);
    assert.equal(next.status, 201, "no takeover needed after the lease ran out");
    const r = await call("/api/v1/run-results", { token: a.token, body: { run_id: run, outcome: outcome({ kills: 3 }) } });
    assert.equal(r.status, 200, "the late result is still accepted");
    clockOffset += 8 * 24 * 60 * 60 * 1000;
    const old = await call("/api/v1/run-results", { token: a.token, body: { run_id: next.json.run.id, outcome: outcome() } });
    assert.equal(old.status, 400, "results older than a week are refused");
    clockOffset = 0;
  });

  test("run results count once, whatever the network does", async () => {
    const a = await player("Gus");
    const run = (await startRun(a)).json.run.id;
    const body = { run_id: run, outcome: outcome({ kills: 45 }) };
    // A double-submit (two tabs, a retry racing the original) grants once.
    const [one, two] = await Promise.all([call("/api/v1/run-results", { token: a.token, body }), call("/api/v1/run-results", { token: a.token, body })]);
    assert.deepEqual([one.status, two.status], [200, 200]);
    assert.deepEqual(one.json, two.json, "the retry gets the original response");
    assert.deepEqual(one.json.result, { zenny: 117, new_unlocks: ["ember", "coil"] });
    // A retry after a lost response, much later.
    const again = await call("/api/v1/run-results", { token: a.token, body });
    assert.deepEqual(again.json, one.json);
    const conflicting = await call("/api/v1/run-results", { token: a.token, body: { run_id: run, outcome: outcome({ scrap: 99999 }) } });
    assert.equal(conflicting.status, 409);
    assert.equal(conflicting.json.error.code, "operation_conflict");
    const r = await call("/api/v1/profile", { token: a.token });
    assert.deepEqual([r.json.profile.zenny, r.json.profile.runs, r.json.profile.kills, r.json.revision], [117, 1, 45, 1]);
    assert.equal(r.json.active_run, null, "finishing ends the run");
    const bad = await call("/api/v1/run-results", { token: a.token, body: { run_id: (await startRun(a)).json.run.id, outcome: outcome({ won: true }) } });
    assert.equal(bad.status, 400, "a win needs three descents and guardians");
  });

  test("purchases are atomic and revision-checked", async () => {
    const a = await player("Hal");
    const run = (await startRun(a)).json.run.id;
    await call("/api/v1/run-results", { token: a.token, body: { run_id: run, outcome: outcome({ won: true, depth: 3, guardians: 3, scrap: 500 }) } });
    let r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.json.profile.zenny, 75 + 180 + 100);
    const revision = r.json.revision;
    r = await call("/api/v1/purchases", { token: a.token, body: { op_id: op(), character: 0, node: "frame", expected_revision: revision - 1 } });
    assert.equal(r.status, 409);
    assert.equal(r.json.error.code, "revision_conflict");
    assert.equal(r.json.revision, revision, "the conflict returns the current profile");
    // Two devices buy at once from the same revision: exactly one wins.
    const [x, y] = await Promise.all([
      call("/api/v1/purchases", { token: a.token, body: { op_id: op(), character: 0, node: "frame", expected_revision: revision } }),
      call("/api/v1/purchases", { token: a.token, body: { op_id: op(), character: 1, node: "frame", expected_revision: revision } }),
    ]);
    assert.deepEqual([x.status, y.status].sort(), [200, 409]);
    r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.json.profile.zenny, 355 - 100, "Zenny spent once");
    const id = op();
    const buy = { op_id: id, character: x.status === 200 ? 0 : 1, node: "mobility", expected_revision: r.json.revision };
    const first = await call("/api/v1/purchases", { token: a.token, body: buy });
    assert.equal(first.status, 200);
    const replay = await call("/api/v1/purchases", { token: a.token, body: buy });
    assert.deepEqual(replay.json, first.json, "a retried purchase doesn't charge twice");
    r = await call("/api/v1/purchases", { token: a.token, body: { ...buy, op_id: op(), node: "mastery", expected_revision: first.json.revision } });
    assert.equal(r.status, 400, "mastery needs the circuit");
    r = await call("/api/v1/purchases", { token: a.token, body: { ...buy, op_id: op(), character: 2, node: "frame", expected_revision: first.json.revision } });
    assert.equal(r.status, 200, "115 Zenny buys a 100 Zenny node");
    r = await call("/api/v1/purchases", { token: a.token, body: { ...buy, op_id: op(), character: 3, node: "frame", expected_revision: r.json.revision } });
    assert.equal(r.status, 400, "15 Zenny doesn't");
    assert.equal((await call("/api/v1/profile", { token: a.token })).json.profile.zenny, 15);
  });

  test("discoveries are an idempotent union", async () => {
    const a = await player("Ivy");
    let r = await call("/api/v1/discoveries", { token: a.token, body: { op_id: op(), parts: ["lens", "coil"] } });
    assert.equal(r.status, 200);
    assert.deepEqual(Object.keys(r.json.profile.discovered).sort(), ["coil", "lens"]);
    const rev = r.json.revision;
    r = await call("/api/v1/discoveries", { token: a.token, body: { op_id: op(), parts: ["lens"] } });
    assert.equal(r.json.revision, rev, "nothing new, no new revision");
    r = await call("/api/v1/discoveries", { token: a.token, body: { op_id: op(), parts: ["excalibur"] } });
    assert.equal(r.status, 400);
  });

  test("a guest profile can be adopted once, into an empty account only", async () => {
    const a = await player("Jo");
    const guest = { version: 2, revision: 40, kills: 140, runs: 9, wins: 2, deepest: 3, best_time: 812.5, zenny: 340, discovered: { lens: true }, trees: { 0: ["frame", "mobility"], 1: ["frame"] }, legacy_unlocks: ["ember"] };
    let r = await call("/api/v1/migrate-guest", { token: a.token, body: { profile: { ...guest, wins: 99 } } });
    assert.equal(r.status, 400, "invalid profiles are refused");
    r = await call("/api/v1/migrate-guest", { token: a.token, body: { profile: guest } });
    assert.equal(r.status, 200);
    assert.deepEqual(r.json.preview, { runs: 9, wins: 2, zenny: 340, kills: 140, trees: 3 });
    const confirm = r.json.confirm;
    r = await call("/api/v1/migrate-guest", { token: a.token, body: { op_id: op(), profile: { ...guest, zenny: 99999 }, confirm } });
    assert.equal(r.status, 400, "the confirmation is bound to the previewed profile");
    const b = await player("Kit");
    r = await call("/api/v1/migrate-guest", { token: b.token, body: { op_id: op(), profile: guest, confirm } });
    assert.equal(r.status, 400, "and to the account");
    r = await call("/api/v1/migrate-guest", { token: a.token, body: { op_id: op(), profile: guest, confirm: confirm + "x" } });
    assert.equal(r.status, 400, "the token must match exactly");
    r = await call("/api/v1/migrate-guest", { token: a.token, body: { op_id: op(), profile: guest, confirm } });
    assert.equal(r.status, 200);
    assert.equal(r.json.profile.zenny, 340);
    assert.deepEqual(r.json.profile.trees, { 0: ["frame", "mobility"], 1: ["frame"] });
    assert.equal(r.json.profile.revision, undefined, "the local revision isn't stored");
    r = await call("/api/v1/migrate-guest", { token: a.token, body: { profile: guest } });
    assert.equal(r.status, 409);
    assert.equal(r.json.error.code, "not_empty", "never merges into existing progress");
    clockOffset += 11 * 60 * 1000;
    const c = await player("Lou");
    const preview = await call("/api/v1/migrate-guest", { token: c.token, body: { profile: guest } });
    clockOffset += 11 * 60 * 1000;
    r = await call("/api/v1/migrate-guest", { token: c.token, body: { op_id: op(), profile: guest, confirm: preview.json.confirm } });
    assert.equal(r.status, 400, "confirmations expire");
    clockOffset = 0;
  });

  class Socket {
    constructor() {
      this.messages = [];
      this.ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
      this.ws.on("message", (data, binary) => { if (!binary) this.messages.push(JSON.parse(data.toString())); });
      this.open = new Promise((resolve) => this.ws.on("open", resolve));
    }
    send(m) { this.ws.send(JSON.stringify(m)); }
    async next(t, timeout = 3000) {
      const start = Date.now();
      while (Date.now() - start < timeout) {
        const i = this.messages.findIndex((m) => m.t === t);
        if (i >= 0) return this.messages.splice(i, 1)[0];
        await new Promise((r) => setTimeout(r, 15));
      }
      throw new Error(`no ${t} message; got ${JSON.stringify(this.messages)}`);
    }
    close() { this.ws.terminate(); }
  }
  const ticketFor = async (who) => (await call("/api/v1/lobby-ticket", { token: who.token, body: {} })).json.ticket;

  test("lobby tickets give the relay a verified identity", async () => {
    const a = await player("Max");
    const ticket = await ticketFor(a);
    assert.match(ticket, /^lt_/);
    const s1 = new Socket();
    await s1.open;
    s1.send({ t: "hello", name: "Max", id: "guest-max", v: 2, ticket });
    // Commands sent before the ticket is checked still run, in order.
    s1.send({ t: "create", name: "Max's Dig", public: false });
    const welcome = await s1.next("welcome");
    assert.equal(welcome.account, true);
    const joined = await s1.next("joined");
    // The same account on a second device takes its place (e.g. moving from PC to handheld).
    const s2 = new Socket();
    await s2.open;
    s2.send({ t: "hello", name: "Max", id: "different-guest-id", v: 2, ticket: await ticketFor(a) });
    await s2.next("welcome");
    s2.send({ t: "join", code: joined.code });
    await s2.next("joined");
    await s1.next("replaced");
    // Reused, forged and expired tickets leave the connection a guest.
    const s3 = new Socket();
    await s3.open;
    s3.send({ t: "hello", name: "Thief", id: "thief", v: 2, ticket });
    assert.equal((await s3.next("error")).code, "bad_ticket", "tickets are single-use");
    assert.equal((await s3.next("welcome")).account, false);
    const s4 = new Socket();
    await s4.open;
    s4.send({ t: "hello", name: "Forger", id: "f", v: 2, ticket: "lt_" + "A".repeat(32) });
    assert.equal((await s4.next("error")).code, "bad_ticket");
    const late = await ticketFor(a);
    clockOffset += 61 * 1000;
    const s5 = new Socket();
    await s5.open;
    s5.send({ t: "hello", name: "Slow", id: "s", v: 2, ticket: late });
    assert.equal((await s5.next("error")).code, "bad_ticket", "tickets expire after a minute");
    clockOffset = 0;
    // A guest can't pose as an account by choosing an acct: id.
    const s6 = new Socket();
    await s6.open;
    s6.send({ t: "hello", name: "Poser", id: `acct:${a.id}`, v: 2 });
    await s6.next("welcome");
    s6.send({ t: "join", code: joined.code });
    await s6.next("joined");
    const entered = await s2.next("entered");
    assert.notEqual(entered.id, `acct:${a.id}`);
    assert.match(entered.id, /^anon-/);
    for (const s of [s1, s2, s3, s4, s5, s6]) s.close();
  });

  test("Windows/Android sign in with a device code", async () => {
    const a = await player("Ned");
    let r = await call("/api/auth/device/code", { body: { client_id: "relic-android" }, origin: null });
    assert.equal(r.status, 200);
    const { device_code, user_code, verification_uri_complete } = r.json;
    assert.ok(verification_uri_complete.includes("/account/device"));
    const poll = () => call("/api/auth/device/token", { origin: null, body: { grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code, client_id: "relic-android" } });
    assert.equal((await poll()).json.error, "authorization_pending");
    // The website looks the code up first, which ties it to the signed-in player.
    r = await call(`/api/auth/device?user_code=${user_code}`, { cookie: a.cookie });
    assert.equal(r.status, 200);
    assert.equal(r.json.client_id, "relic-android");
    const other = await player("Nosy");
    r = await call("/api/auth/device/approve", { cookie: other.cookie, body: { userCode: user_code } });
    assert.equal(r.status, 403, "someone else can't approve a code another player is looking at");
    r = await call("/api/auth/device/approve", { cookie: a.cookie, body: { userCode: user_code } });
    assert.equal(r.status, 200);
    await new Promise((res) => setTimeout(res, 5200));
    r = await poll();
    assert.equal(r.status, 200);
    const token = r.json.access_token;
    const profile = await call("/api/v1/profile", { token });
    assert.equal(profile.json.account.id, a.id, "the device signs in as the approving account");
    assert.equal((await poll()).json.error, "invalid_grant", "codes redeem once");
    r = await call("/api/auth/device/code", { body: { client_id: "someone-else" }, origin: null });
    assert.ok(r.status >= 400, "unknown clients can't request codes");
    // A denied code never yields a token.
    r = await call("/api/auth/device/code", { body: { client_id: "relic-windows" }, origin: null });
    await call(`/api/auth/device?user_code=${r.json.user_code}`, { cookie: a.cookie });
    await call("/api/auth/device/deny", { cookie: a.cookie, body: { userCode: r.json.user_code } });
    await new Promise((res) => setTimeout(res, 5200));
    const denied = await call("/api/auth/device/token", { origin: null, body: { grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: r.json.device_code, client_id: "relic-windows" } });
    assert.equal(denied.json.error, "access_denied");
  });

  test("sign-out and password reset end sessions", async () => {
    const a = await player("Oz");
    let r = await call("/api/auth/sign-out", { token: a.token, body: {} });
    assert.equal(r.status, 200);
    assert.equal((await call("/api/v1/profile", { token: a.token })).status, 401);
    r = await call("/api/auth/sign-in/email", { body: { email: a.email, password: a.password } });
    const token = r.headers.get("set-auth-token");
    await call("/api/auth/request-password-reset", { body: { email: a.email, redirectTo: "/account?reset=1" } });
    const link = mail.findLast((m) => m.to === a.email && m.kind === "reset");
    assert.ok(link, "reset mail sent");
    const resetToken = new URL((await fetch(link.url, { redirect: "manual" })).headers.get("location"), base).searchParams.get("token");
    r = await call("/api/auth/reset-password", { body: { newPassword: "a brand new secret", token: resetToken } });
    assert.equal(r.status, 200);
    assert.equal((await call("/api/v1/profile", { token })).status, 401, "resetting the password signs other devices out");
    r = await call("/api/auth/reset-password", { body: { newPassword: "another new secret", token: resetToken } });
    assert.ok(r.status >= 400, "reset links work once");
  });

  test("deleting an account removes its progress and old receipts can't come back", async () => {
    const a = await player("Pip");
    const run = (await startRun(a)).json.run.id;
    const receipt = { run_id: run, outcome: outcome() };
    await call("/api/v1/run-results", { token: a.token, body: receipt });
    const r = await call("/api/auth/delete-user", { cookie: a.cookie, body: { password: a.password } });
    assert.equal(r.status, 200, r.text);
    assert.equal((await call("/api/v1/profile", { token: a.token })).status, 401);
    const left = await pool.query(`select count(*)::int as n from game_account where id = $1`, [a.id]);
    assert.equal(left.rows[0].n, 0, "the game account and its rows are gone");
    // Re-registering the same email is a brand-new account; the old receipt doesn't apply.
    mail.length = 0;
    let s = await call("/api/auth/sign-up/email", { body: { name: "Pip", email: a.email, password: a.password } });
    assert.equal(s.status, 200);
    await fetch(mail.findLast((m) => m.to === a.email).url, { redirect: "manual" });
    s = await call("/api/auth/sign-in/email", { body: { email: a.email, password: a.password } });
    const token = s.headers.get("set-auth-token");
    const replay = await call("/api/v1/run-results", { token, body: receipt });
    assert.equal(replay.status, 404);
    const fresh = await call("/api/v1/profile", { token });
    assert.notEqual(fresh.json.account.id, a.id);
    assert.equal(fresh.json.profile.zenny, 0);
  });

  test("the admin role comes only from the operator, and only verified accounts get it", async () => {
    const a = await player("Quinn");
    const user = (await pool.query(`select user_id from game_account where id = $1`, [a.id])).rows[0].user_id;
    await pool.query(`update "user" set role = 'admin' where id = $1`, [user]);
    const r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.json.account.role, "admin");
  });

  test("progress survives a server restart", async () => {
    const a = await player("Rae");
    const run = (await startRun(a)).json.run.id;
    await call("/api/v1/run-results", { token: a.token, body: { run_id: run, outcome: outcome() } });
    await app.close();
    await pool.end();
    pool = createPool(dbUrl, () => {});
    await startApp();
    const r = await call("/api/v1/profile", { token: a.token });
    assert.equal(r.status, 200, "sessions survive too");
    assert.equal(r.json.profile.zenny, 117);
  });

  test("rate limits answer 429 with Retry-After", async () => {
    const limited = await createAccounts({ pool, secret: SECRET, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 1000, account: 3 }, log: () => {} });
    const server = createServer({ port: 0, webRoot, log: () => {}, accounts: limited });
    const p = await server.listen();
    const a = await player("Sol");
    const statuses = [];
    for (let i = 0; i < 5; i++) statuses.push((await fetch(`http://127.0.0.1:${p}/api/v1/profile`, { headers: { Authorization: `Bearer ${a.token}` } })).status);
    assert.deepEqual(statuses, [200, 200, 200, 429, 429]);
    const r = await fetch(`http://127.0.0.1:${p}/api/v1/profile`, { headers: { Authorization: `Bearer ${a.token}` } });
    assert.equal(r.headers.get("retry-after"), "60");
    await new Promise((res) => server.server.close(res));
  });

  test("without mail, sign-up and reset are refused instead of creating unverifiable accounts", async () => {
    const noMail = await createAccounts({ pool, secret: SECRET, origin: base, rateLimit: false, log: () => {} });
    const server = createServer({ port: 0, webRoot, log: () => {}, accounts: noMail });
    const p = await server.listen();
    const r = await fetch(`http://127.0.0.1:${p}/api/auth/sign-up/email`, { method: "POST", headers: { "Content-Type": "application/json", Origin: base }, body: JSON.stringify({ name: "X", email: "x@example.test", password: "correct horse battery" }) });
    assert.equal(r.status, 503);
    assert.equal((await r.json()).code, "mail_unavailable");
    await new Promise((res) => server.server.close(res));
  });

  test("account pages are served with a strict policy", async () => {
    for (const page of ["/account", "/account/device"]) {
      const r = await fetch(base + page);
      assert.equal(r.status, 200);
      assert.match(r.headers.get("content-security-policy"), /script-src 'self'/);
      assert.equal(r.headers.get("x-frame-options"), "DENY");
      assert.match(await r.text(), /\/account\/app\.js/);
    }
    assert.match(await (await fetch(base + "/account/app.js")).text(), /device\/approve/);
  });
});
