// Relic Diver web host and co-op lobby relay.
//
//   PORT       HTTP port (default 8080)
//   WEB_ROOT   exported Godot web build (default ../build/web)
//   MAX_LOBBIES  concurrent lobby cap (default 200)
//   RUN_GRACE_MINUTES  how long an empty lobby with a dig in progress waits for its diggers (default 15)
//   DATABASE_URL, BETTER_AUTH_SECRET, PUBLIC_ORIGIN, MAIL_URL, MAIL_FROM
//              turn on accounts (docs/ACCOUNT-API.md); without them the server is guest-only
//
// Serves the game with the cross-origin isolation headers Godot's threaded web
// build needs, and upgrades /ws to the lobby protocol described in lobby.js.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { WebSocketServer } from "ws";
import { LobbyRegistry, CHECKPOINT_TARGET, cleanCode, cleanText, routePacket } from "./lobby.js";
import { createAccounts } from "./accounts/api.js";
import { androidReleases } from "./android-updates.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const PROTOCOL_VERSION = 2;
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".svg": "image/svg+xml",
  ".json": "application/json",
  ".txt": "text/plain; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".md": "text/plain; charset=utf-8",
  ".ttf": "font/ttf",
};
const COMPRESSIBLE = new Set([".html", ".js", ".wasm", ".pck", ".json", ".svg", ".txt", ".css", ".md", ".ttf"]);

export function createServer({ port = 8080, webRoot = path.join(here, "..", "build", "web"), maxLobbies = 200, log = console.log, runGraceMs, idleGraceMs, accounts = null, androidReleaseDir = process.env.ANDROID_RELEASE_DIR } = {}) {
  const android = androidReleases(androidReleaseDir);
  const registry = new LobbyRegistry({ maxLobbies, runGraceMs, idleGraceMs });
  const compressed = new Map();
  const root = path.resolve(webRoot);

  function securityHeaders(res) {
    res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
    res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
    res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Referrer-Policy", "same-origin");
  }

  const brotliOptions = (size) => ({ params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 9, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: size } });
  const cacheKey = (file, stat, encoding) => `${file}|${stat.mtimeMs}|${stat.size}|${encoding}`;

  const brotli = promisify(zlib.brotliCompress);
  const gzip = promisify(zlib.gzip);

  // Compressed bodies are cached as promises so concurrent requests share the work.
  function encoded(file, stat, encoding) {
    const key = cacheKey(file, stat, encoding);
    let entry = compressed.get(key);
    if (!entry) {
      for (const old of compressed.keys()) if (old.startsWith(`${file}|`) && old.endsWith(`|${encoding}`)) compressed.delete(old);
      entry = fs.promises.readFile(file).then((raw) => (encoding === "br" ? brotli(raw, brotliOptions(raw.length)) : gzip(raw, { level: 9 })));
      entry.catch(() => compressed.delete(key));
      compressed.set(key, entry);
    }
    return entry;
  }

  // Compress the large game files in the background so the first visitor doesn't wait.
  async function warmCache() {
    let names = [];
    try {
      names = fs.readdirSync(root);
    } catch {
      return;
    }
    for (const name of names) {
      const file = path.join(root, name);
      const stat = fs.statSync(file);
      if (!stat.isFile() || stat.size < 1024 || !COMPRESSIBLE.has(path.extname(name).toLowerCase())) continue;
      for (const encoding of ["br", "gzip"]) await encoded(file, stat, encoding);
    }
  }

  function serveStatic(req, res, pathname) {
    let relative = decodeURIComponent(pathname);
    if (relative === "/" || relative === "") relative = "/index.html";
    const file = path.resolve(root, "." + relative);
    if (!file.startsWith(root + path.sep)) return notFound(res);
    let stat;
    try {
      stat = fs.statSync(file);
    } catch {
      return notFound(res);
    }
    if (!stat.isFile()) return notFound(res);
    const ext = path.extname(file).toLowerCase();
    const etag = `"${stat.size.toString(16)}-${Math.floor(stat.mtimeMs).toString(16)}"`;
    securityHeaders(res);
    res.setHeader("Content-Type", MIME[ext] || "application/octet-stream");
    // Re-exports keep the same file names, so revalidate everything cheaply by ETag.
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("ETag", etag);
    res.setHeader("Vary", "Accept-Encoding");
    if (req.headers["if-none-match"] === etag) {
      res.writeHead(304);
      return res.end();
    }
    const accept = String(req.headers["accept-encoding"] || "");
    const encoding = !COMPRESSIBLE.has(ext) || stat.size < 1024 ? null : /\bbr\b/.test(accept) ? "br" : /\bgzip\b/.test(accept) ? "gzip" : null;
    if (encoding) {
      return encoded(file, stat, encoding).then((body) => {
        res.setHeader("Content-Encoding", encoding);
        res.setHeader("Content-Length", body.length);
        res.writeHead(200);
        res.end(req.method === "HEAD" ? undefined : body);
      }, () => {
        res.writeHead(500);
        res.end();
      });
    }
    res.setHeader("Content-Length", stat.size);
    res.writeHead(200);
    if (req.method === "HEAD") return res.end();
    fs.createReadStream(file).pipe(res);
  }

  function notFound(res) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
  }

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (android.handle(req, res, url)) return;
    if (accounts && accounts.handle(req, res, url)) return;
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405, { Allow: "GET, HEAD" });
      return res.end();
    }
    if (url.pathname === "/healthz") {
      res.writeHead(200, { "Content-Type": "text/plain" });
      return res.end("ok");
    }
    if (url.pathname === "/api/lobbies") {
      res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
      return res.end(JSON.stringify({ lobbies: registry.publicList() }));
    }
    // Short invite links: /j/CODE → /?lobby=CODE
    const invite = url.pathname.match(/^\/j\/([A-Za-z0-9]{3,12})\/?$/);
    if (invite) {
      res.writeHead(302, { Location: `/?lobby=${invite[1].toUpperCase()}` });
      return res.end();
    }
    serveStatic(req, res, url.pathname);
  });

  const wss = new WebSocketServer({ noServer: true, maxPayload: 512 * 1024, perMessageDeflate: false });
  let nextId = 1;

  server.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname !== "/ws") return socket.destroy();
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
  });

  function send(client, message) {
    if (client.ws.readyState === client.ws.OPEN) client.ws.send(JSON.stringify(message));
  }

  function broadcastLobby(lobby) {
    const description = registry.describe(lobby);
    for (const member of lobby.members.values()) send(member, { t: "lobby", lobby: description, slot: member.slot });
  }

  // Tell the remaining members someone left, and who hosts now.
  function announceLeave(result) {
    if (!result) return;
    const { lobby, slot, newHost } = result;
    for (const member of lobby.members.values()) {
      send(member, { t: "left", slot });
      if (newHost) send(member, { t: "host", slot: newHost });
    }
    if (newHost) log(`lobby ${lobby.code}: host moved to slot ${newHost}`);
    if (lobby.members.size === 0) log(`lobby ${lobby.code} is empty; keeping it for returning diggers`);
    else broadcastLobby(lobby);
  }

  function leave(client) {
    announceLeave(registry.leave(client));
  }

  function enter(client, outcome, extra = {}) {
    const { lobby, takeover, replaced, replacedResult } = outcome;
    if (replaced) {
      send(replaced, { t: "replaced" });
      announceLeave(replacedResult);
    }
    const checkpoint = takeover && lobby.state === "run" && lobby.checkpoint;
    send(client, { t: "joined", code: lobby.code, slot: client.slot, hostSlot: lobby.hostSlot, takeover, checkpoint: Boolean(checkpoint), password: lobby.password, ...extra });
    if (checkpoint) client.ws.send(Buffer.concat([Buffer.from([CHECKPOINT_TARGET]), checkpoint]), { binary: true });
    for (const member of lobby.members.values()) if (member !== client) send(member, { t: "entered", slot: client.slot, name: client.name, id: client.playerId });
    broadcastLobby(lobby);
  }

  function isHost(client) {
    return client.lobby && client.slot === client.lobby.hostSlot;
  }

  function handleCommand(client, message) {
    switch (message.t) {
      case "hello": {
        const release = android.current();
        if (message.platform === 'android' && release && (!Number.isInteger(message.androidVersionCode) || message.androidVersionCode < release.minimumOnlineVersionCode || message.v !== release.gameProtocol)) {
          client.updateBlocked = true;
          send(client, { t:'error', code:'update_required' });
          client.ws.close(1008, 'Android update required');
          return;
        }
        client.name = cleanText(message.name, 16) || "Digger";
        // Guests pick their own id; "acct:" ids are reserved for verified accounts.
        const guestId = cleanText(message.id, 40);
        client.playerId = guestId && !guestId.startsWith("acct:") ? guestId : `anon-${client.id}`;
        client.accountId = null;
        client.version = Number.isInteger(message.v) ? message.v : 0;
        if (message.ticket === undefined || !accounts) return send(client, { t: "welcome", id: client.id, v: PROTOCOL_VERSION });
        // Commands that arrive while the ticket is checked wait their turn.
        client.waiting = [];
        accounts.redeemTicket(message.ticket).catch(() => null).then((accountId) => {
          if (accountId) {
            client.accountId = accountId;
            client.playerId = `acct:${accountId}`;
          } else send(client, { t: "error", code: "bad_ticket" });
          send(client, { t: "welcome", id: client.id, v: PROTOCOL_VERSION, account: Boolean(accountId) });
          const queued = client.waiting;
          client.waiting = null;
          for (const next of queued) handleCommand(client, next);
        });
        return;
      }
      case "name":
        client.name = cleanText(message.name, 16) || client.name;
        if (client.lobby) broadcastLobby(client.lobby);
        return;
      case "list":
        return send(client, { t: "lobbies", lobbies: registry.publicList() });
      case "create": {
        leave(client);
        const outcome = registry.create(client, { name: message.name, isPublic: message.public, password: message.password });
        if (outcome.error) return send(client, { t: "error", code: outcome.error });
        log(`lobby ${outcome.lobby.code} created by ${client.name}`);
        return enter(client, outcome);
      }
      case "join":
      case "resume": {
        const code = cleanCode(message.code);
        if (client.lobby && client.lobby.code === code) return;
        leave(client);
        let outcome = registry.join(client, code, message.password);
        // Resuming a lobby the server forgot (e.g. after a restart) recreates it under the same code.
        if (outcome.error === "not_found" && message.t === "resume") {
          outcome = registry.create(client, { name: message.name, isPublic: message.public, password: message.password, code });
          if (!outcome.error) return enter(client, outcome, { recreated: true });
        }
        if (outcome.error) return send(client, { t: "error", code: outcome.error });
        return enter(client, outcome);
      }
      case "leave":
        return leave(client);
      case "kick": {
        const target = registry.kick(client, Number(message.slot));
        if (!target) return;
        send(target, { t: "kicked" });
        for (const member of client.lobby.members.values()) send(member, { t: "left", slot: Number(message.slot) });
        return broadcastLobby(client.lobby);
      }
      case "lock":
        if (!isHost(client)) return;
        client.lobby.locked = message.locked === true;
        return broadcastLobby(client.lobby);
      case "status":
        // The host reports whether a run is underway so the browser can show it.
        if (!isHost(client)) return;
        client.lobby.state = message.state === "run" ? "run" : "lobby";
        client.lobby.depth = Math.max(1, Math.min(3, Number(message.depth) || 1));
        if (client.lobby.state === "lobby") client.lobby.checkpoint = null;
        return broadcastLobby(client.lobby);
      case "ping":
        return send(client, { t: "pong", time: message.time });
      default:
        return send(client, { t: "error", code: "unknown_command" });
    }
  }

  wss.on("connection", (ws) => {
    const client = { id: nextId++, ws, name: "Digger", playerId: "", accountId: null, waiting: null, version: 0, lobby: null, slot: 0, tokens: 480, stamp: Date.now() };
    client.playerId = `anon-${client.id}`;
    ws.on("message", (data, isBinary) => {
      if (client.updateBlocked) return;
      // Token bucket: generous for 60 Hz batched game traffic, closes floods.
      const now = Date.now();
      client.tokens = Math.min(480, client.tokens + ((now - client.stamp) / 1000) * 240);
      client.stamp = now;
      if (--client.tokens < 0) return ws.close(1008, "rate limit");
      if (isBinary) {
        if (client.waiting) return;
        const routed = routePacket(client, Buffer.isBuffer(data) ? data : Buffer.concat(data));
        if (!routed) return;
        for (const member of routed.recipients) if (member.ws.readyState === member.ws.OPEN) member.ws.send(routed.out, { binary: true });
        return;
      }
      if (data.length > 4096) return send(client, { t: "error", code: "too_large" });
      let message;
      try {
        message = JSON.parse(data.toString());
      } catch {
        return send(client, { t: "error", code: "bad_json" });
      }
      if (!message || typeof message.t !== "string") return;
      if (client.waiting) {
        if (client.waiting.length < 32) client.waiting.push(message);
        return;
      }
      handleCommand(client, message);
    });
    ws.on("close", () => leave(client));
    ws.on("error", () => {});
  });

  // Expire abandoned lobbies even when nobody asks for the list.
  const pruner = setInterval(() => registry.prune(), 60000);

  // Keep idle sockets alive through Cloudflare (100 s idle limit) and reap dead ones.
  const heartbeat = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.relicAlive === false) return ws.terminate();
      ws.relicAlive = false;
      ws.ping();
    });
  }, 25000);
  wss.on("connection", (ws) => {
    ws.relicAlive = true;
    ws.on("pong", () => { ws.relicAlive = true; });
  });
  server.on("close", () => {
    clearInterval(heartbeat);
    clearInterval(pruner);
  });

  return {
    server,
    registry,
    warmCache,
    listen() {
      return new Promise((resolve) => server.listen(port, () => resolve(server.address().port)));
    },
    close() {
      for (const ws of wss.clients) ws.terminate();
      return new Promise((resolve) => server.close(() => resolve())).then(() => accounts?.close());
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let accounts = null;
  if (process.env.DATABASE_URL) {
    try {
      accounts = await createAccounts({ databaseUrl: process.env.DATABASE_URL, secret: process.env.BETTER_AUTH_SECRET, origin: process.env.PUBLIC_ORIGIN, mailUrl: process.env.MAIL_URL, mailFrom: process.env.MAIL_FROM });
      console.log(`Accounts enabled for ${process.env.PUBLIC_ORIGIN}${process.env.MAIL_URL ? "" : " (no MAIL_URL: sign-up is off)"}`);
    } catch (error) {
      console.error(`Accounts could not start: ${error.message}`);
      process.exit(1);
    }
  }
  const app = createServer({
    accounts,
    port: Number(process.env.PORT) || 8080,
    webRoot: process.env.WEB_ROOT || path.join(here, "..", "build", "web"),
    maxLobbies: Number(process.env.MAX_LOBBIES) || 200,
    runGraceMs: (Number(process.env.RUN_GRACE_MINUTES) || 15) * 60000,
  });
  app.listen().then((port) => {
    console.log(`Relic Diver server listening on http://0.0.0.0:${port}`);
    const started = Date.now();
    app.warmCache().then(() => console.log(`Game files compressed in ${((Date.now() - started) / 1000).toFixed(1)} s`));
  });
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => app.close().then(() => process.exit(0)));
}
