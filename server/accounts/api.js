// Accounts for the Relic Diver server: Better Auth under /api/auth, the game's
// progress API under /api/v1, and the account web pages under /account.
// See docs/ACCOUNT-API.md for the contract.
import crypto from "node:crypto";
import { toNodeHandler, fromNodeHeaders } from "better-auth/node";
import { createAuth, authOptions } from "./auth.js";
import { createPool, schemaReady } from "./db.js";
import { createMailer } from "./mail.js";
import { createStore, ApiError } from "./store.js";
import { accountPage, devicePage, pageAsset } from "./pages.js";
import { adminPage, adminAsset } from "./admin-page.js";
import { createAnalytics, utcDay } from "./analytics.js";
import { validateOutcome } from "./rules.js";

const MAX_BODY = 16 * 1024;
// An authenticator check unlocks /admin for this long on that session.
const ADMIN_MFA_MS = 12 * 60 * 60 * 1000;
const MAX_STATS_DAYS = 366;

export async function createAccounts({ databaseUrl, pool: givenPool, secret, origin, mailUrl, mailFrom, mailSink, rateLimit = true, apiLimits = { ip: 120, account: 60 }, now = () => Date.now(), log = console.log }) {
  if (!secret || secret.length < 32) throw new Error("BETTER_AUTH_SECRET must be at least 32 characters.");
  if (!origin || !/^https?:\/\/[^/]+$/.test(origin)) throw new Error("PUBLIC_ORIGIN must be an origin like https://example.com.");
  const pool = givenPool || createPool(databaseUrl);
  const mailer = createMailer({ url: mailUrl, from: mailFrom, sink: mailSink });
  const analytics = createAnalytics({ pool, now, log });
  const options = { pool, secret, origin, mailer, rateLimit, analytics };
  if (!(await schemaReady(pool, authOptions(options)))) throw new Error("The account database schema is out of date. Run `node server/migrate.js` first.");
  const auth = createAuth(options);
  const authHandler = toNodeHandler(auth);
  const store = createStore({ pool, secret, now });
  const limits = new Map();
  let live = () => null;
  // Summaries before retention, hourly; failures are logged and retried next hour.
  const maintain = () => analytics.prune().catch((error) => log(`analytics maintenance: ${error.message}`));
  const maintenance = setInterval(maintain, 60 * 60 * 1000);
  maintenance.unref();

  function limited(key, max) {
    const minute = Math.floor(Date.now() / 60000);
    const entry = limits.get(key);
    if (!entry || entry.minute !== minute) {
      limits.set(key, { minute, count: 1 });
      return false;
    }
    return ++entry.count > max;
  }
  const pruneLimits = setInterval(() => {
    const minute = Math.floor(Date.now() / 60000);
    for (const [key, entry] of limits) if (entry.minute !== minute) limits.delete(key);
  }, 60000);
  pruneLimits.unref();

  function clientIp(req) {
    return String(req.headers["cf-connecting-ip"] || req.headers["x-forwarded-for"] || req.socket.remoteAddress || "").split(",")[0].trim();
  }

  function sendJson(res, status, body, headers = {}) {
    res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers });
    res.end(JSON.stringify(body));
  }

  function sendError(res, error, requestId, who = null) {
    if (who && error instanceof ApiError && error.status !== 429) analytics.record({ kind: "api_error", outcome: error.code, accountId: who.account.id });
    if (!(error instanceof ApiError)) {
      log(`account api ${requestId}: ${error.stack || error}`);
      error = new ApiError(503, "unavailable", "The save service had a problem. Your progress is kept on this device; try again shortly.");
    }
    const headers = error.code === "rate_limited" ? { "Retry-After": "60" } : {};
    sendJson(res, error.status, { error: { code: error.code, message: error.message, request_id: requestId }, ...error.extra }, headers);
  }

  // Oversized bodies are drained (up to 1 MB) so the client still gets a clean 413.
  function readBody(req) {
    return new Promise((resolve, reject) => {
      let size = 0;
      const chunks = [];
      req.on("data", (chunk) => {
        size += chunk.length;
        if (size <= MAX_BODY) chunks.push(chunk);
        else if (size > 1024 * 1024) req.destroy();
      });
      req.on("end", () => {
        if (size > MAX_BODY) return reject(new ApiError(413, "too_large", "Request body is too large."));
        if (size === 0) return resolve({});
        try {
          const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
          if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
          resolve(body);
        } catch {
          reject(new ApiError(400, "validation", "Body must be a JSON object."));
        }
      });
      req.on("error", reject);
    });
  }

  // Resolves the signed-in, verified user and their game account.
  async function authenticate(req) {
    const bearer = typeof req.headers.authorization === "string" && req.headers.authorization.startsWith("Bearer ");
    // Cookie sessions are ambient, so writes must come from the game's own pages.
    if (!bearer && req.method !== "GET" && req.headers.origin !== origin) throw new ApiError(403, "forbidden", "Cross-site request refused.");
    if (limited(`ip:${clientIp(req)}`, apiLimits.ip)) throw new ApiError(429, "rate_limited", "Too many requests. Wait a minute and try again.");
    const session = await auth.api.getSession({ headers: fromNodeHeaders(req.headers) });
    if (!session) throw new ApiError(401, "unauthorized", "Sign in to continue.");
    if (!session.user.emailVerified) throw new ApiError(403, "unverified", "Confirm your email address to save progress to your account.");
    const account = await store.ensureAccount(session.user);
    if (limited(`acct:${account.id}`, apiLimits.account)) throw new ApiError(429, "rate_limited", "Too many requests. Wait a minute and try again.");
    return { account, role: session.user.role === "admin" ? "admin" : "player" };
  }

  // Admin data needs a browser cookie session (never a game bearer token), the
  // admin role, a verified email, an enabled authenticator and a recent
  // authenticator check on this very session. Signing out deletes the session
  // and with it the check.
  async function authenticateAdmin(req) {
    if (typeof req.headers.authorization === "string") throw new ApiError(403, "forbidden", "Admin pages need a browser sign-in.");
    if (limited(`ip:${clientIp(req)}`, apiLimits.ip)) throw new ApiError(429, "rate_limited", "Too many requests. Wait a minute and try again.");
    const session = await auth.api.getSession({ headers: fromNodeHeaders(req.headers) });
    if (!session) throw new ApiError(401, "unauthorized", "Sign in to continue.");
    if (session.user.role !== "admin" || !session.user.emailVerified) throw new ApiError(403, "forbidden", "This page is for the game's owner.");
    if (!session.user.twoFactorEnabled) throw new ApiError(403, "mfa_setup_required", "Set up an authenticator app on your account page first.");
    const mark = (await pool.query(`select verified_at from admin_mfa_session where session_id = $1`, [session.session.id])).rows[0];
    if (!mark || now() - mark.verified_at.getTime() > ADMIN_MFA_MS) throw new ApiError(403, "mfa_required", "Enter a code from your authenticator app.");
    return { user: session.user };
  }

  function dateParam(value, fallback) {
    if (value === null || value === "") return fallback;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value + "T00:00:00Z")) || utcDay(Date.parse(value + "T00:00:00Z")) !== value) throw new ApiError(400, "validation", "Dates must be YYYY-MM-DD (UTC).");
    return value;
  }

  const adminRoutes = [
    [/^\/api\/admin\/me$/, async ({ user }) => ({ name: user.name, email: user.email })],
    [/^\/api\/admin\/stats$/, async (who, url) => {
      const today = utcDay(now());
      const to = dateParam(url.searchParams.get("to"), today);
      const from = dateParam(url.searchParams.get("from"), utcDay(Date.parse(to + "T00:00:00Z") - 29 * 86400000));
      if (from > to) throw new ApiError(400, "validation", "from must not be after to.");
      if ((Date.parse(to) - Date.parse(from)) / 86400000 + 1 > MAX_STATS_DAYS) throw new ApiError(400, "validation", `At most ${MAX_STATS_DAYS} days at once.`);
      return { ...(await analytics.stats(from, to)), live: live() };
    }],
    [/^\/api\/admin\/users$/, async (who, url) => analytics.users({ q: url.searchParams.get("q") || "", page: url.searchParams.get("page") || 1 })],
    [/^\/api\/admin\/users\/(acc_[A-Za-z0-9_-]+)$/, async (who, url, match) => {
      const detail = await analytics.user(match[1]);
      if (!detail) throw new ApiError(404, "not_found", "No such account.");
      return detail;
    }],
  ];

  async function handleAdmin(req, res, url) {
    const requestId = "req_" + crypto.randomBytes(8).toString("hex");
    try {
      const route = adminRoutes.find(([pattern]) => pattern.test(url.pathname));
      if (!route) throw new ApiError(404, "not_found", "No such endpoint.");
      if (req.method !== "GET") throw new ApiError(405, "validation", "The dashboard is read-only.");
      const who = await authenticateAdmin(req);
      sendJson(res, 200, await route[1](who, url, url.pathname.match(route[0])), { "Cross-Origin-Resource-Policy": "same-origin", "X-Content-Type-Options": "nosniff" });
    } catch (error) {
      sendError(res, error, requestId);
    }
  }

  const routes = [
    ["GET", /^\/api\/v1\/profile$/, async ({ account, role }) => [200, await store.getProfile(account, role)]],
    ["POST", /^\/api\/v1\/runs$/, async ({ account, role }, body) => store.startRun(account, role, body)],
    ["POST", /^\/api\/v1\/runs\/(run_[A-Za-z0-9_-]+)\/heartbeat$/, async ({ account }, body, match) => [200, await store.heartbeat(account, match[1])]],
    ["POST", /^\/api\/v1\/run-results$/, async ({ account, role }, body) => store.finishRun(account, role, body)],
    ["POST", /^\/api\/v1\/purchases$/, async ({ account, role }, body) => store.purchase(account, role, body)],
    ["POST", /^\/api\/v1\/discoveries$/, async ({ account, role }, body) => store.discover(account, role, body)],
    ["POST", /^\/api\/v1\/migrate-guest$/, async ({ account, role }, body) => store.migrateGuest(account, role, body)],
    ["POST", /^\/api\/v1\/lobby-ticket$/, async ({ account }) => [200, await store.issueTicket(account)]],
    // Foreground play-time estimate (phase 6). Not part of the outbox; losing one is fine.
    ["POST", /^\/api\/v1\/activity$/, async ({ account }, body) => {
      if (!Number.isInteger(body.seconds) || body.seconds < 1 || body.seconds > 3600) throw new ApiError(400, "validation", "seconds must be an integer from 1 to 3600.");
      return [200, await analytics.activity(account.id, body.platform, body.seconds)];
    }],
  ];

  // Dashboard events for first-time (non-replayed) progress operations.
  async function observe(pathname, who, body, result) {
    if (result.replayed) return analytics.record({ kind: "replay", accountId: who.account.id });
    if (result.status >= 300) return;
    if (pathname === "/api/v1/runs") {
      await analytics.record({ kind: "run_start", accountId: who.account.id, platform: body.platform, gameVersion: body.game_version });
      await analytics.activity(who.account.id, body.platform).catch(() => {});
    } else if (pathname === "/api/v1/run-results") {
      const o = validateOutcome(body.outcome);
      await analytics.record({ kind: "run_result", accountId: who.account.id, data: { won: o.won, abandoned: o.abandoned, depth: o.depth, guardians: o.guardians, character: o.character } });
    }
  }

  async function handleApi(req, res, pathname) {
    const requestId = "req_" + crypto.randomBytes(8).toString("hex");
    let who = null;
    try {
      const route = routes.find(([method, pattern]) => pattern.test(pathname) && method === req.method);
      if (!route) {
        const exists = routes.some(([, pattern]) => pattern.test(pathname));
        throw exists ? new ApiError(405, "validation", "Method not allowed.") : new ApiError(404, "not_found", "No such endpoint.");
      }
      who = await authenticate(req);
      const body = req.method === "POST" ? await readBody(req) : {};
      const result = await route[2](who, body, pathname.match(route[1]));
      const [status, payload] = Array.isArray(result) ? result : [result.status, result.body];
      if (!Array.isArray(result)) await observe(pathname, who, body, result);
      sendJson(res, status, payload);
    } catch (error) {
      sendError(res, error, requestId, who);
    }
  }

  // Unless mail delivery works, refuse the flows that depend on it rather than
  // creating accounts nobody can verify.
  function mailGuard(req, res, pathname) {
    if (mailer.available || req.method !== "POST") return false;
    if (!["/api/auth/sign-up/email", "/api/auth/request-password-reset", "/api/auth/send-verification-email"].includes(pathname)) return false;
    sendJson(res, 503, { code: "mail_unavailable", message: "Account emails aren't set up on this server yet, so new accounts can't be created." });
    return true;
  }

  return {
    // Returns true when the request was an account route and has been answered.
    handle(req, res, url) {
      const { pathname } = url;
      if (pathname.startsWith("/api/auth/")) {
        if (!mailGuard(req, res, pathname)) authHandler(req, res);
        return true;
      }
      if (pathname.startsWith("/api/v1/")) {
        handleApi(req, res, pathname);
        return true;
      }
      if (pathname === "/account" || pathname === "/account/") return accountPage(res), true;
      if (pathname === "/account/device") return devicePage(res), true;
      if (pathname === "/account/app.js" || pathname === "/account/app.css") return pageAsset(res, pathname.slice(9)), true;
      if (pathname.startsWith("/api/admin/")) return handleAdmin(req, res, url), true;
      if (pathname === "/admin" || pathname === "/admin/") return adminPage(res), true;
      if (pathname === "/admin/app.js" || pathname === "/admin/app.css") return adminAsset(res, pathname.slice(7)), true;
      return false;
    },
    redeemTicket: (ticket) => store.redeemTicket(ticket),
    // The relay reports current connections and lobbies for the dashboard.
    setLive(fn) { live = fn; },
    analytics,
    auth,
    pool,
    async close() {
      clearInterval(pruneLimits);
      clearInterval(maintenance);
      if (!givenPool) await pool.end();
    },
  };
}
