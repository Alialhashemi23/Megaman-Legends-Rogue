import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { WebSocket } from "ws";
import { createServer } from "../server.js";
import { LobbyRegistry, cleanText } from "../lobby.js";

let app;
let port;
let webRoot;

before(async () => {
  webRoot = fs.mkdtempSync(path.join(os.tmpdir(), "relic-web-"));
  fs.writeFileSync(path.join(webRoot, "index.html"), "<!doctype html><title>Relic Diver</title>" + "x".repeat(4000));
  fs.writeFileSync(path.join(webRoot, "index.wasm"), Buffer.alloc(5000, 7));
  app = createServer({ port: 0, webRoot, log: () => {} });
  port = await app.listen();
});

after(async () => {
  await app.close();
  fs.rmSync(webRoot, { recursive: true, force: true });
});

class Client {
  constructor(name) {
    this.name = name;
    this.queue = [];
    this.waiters = [];
  }
  async open() {
    this.ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    this.ws.on("message", (data, isBinary) => {
      const message = isBinary ? { binary: Buffer.from(data) } : JSON.parse(data.toString());
      const waiter = this.waiters.findIndex((w) => w.match(message));
      if (waiter >= 0) this.waiters.splice(waiter, 1)[0].resolve(message);
      else this.queue.push(message);
    });
    await new Promise((resolve, reject) => { this.ws.once("open", resolve); this.ws.once("error", reject); });
    this.send({ t: "hello", name: this.name });
    await this.next((m) => m.t === "welcome");
    return this;
  }
  send(message) { this.ws.send(JSON.stringify(message)); }
  next(match, timeout = 2000) {
    const index = this.queue.findIndex(match);
    if (index >= 0) return Promise.resolve(this.queue.splice(index, 1)[0]);
    return new Promise((resolve, reject) => {
      const waiter = { match, resolve };
      this.waiters.push(waiter);
      setTimeout(() => {
        const i = this.waiters.indexOf(waiter);
        if (i >= 0) { this.waiters.splice(i, 1); reject(new Error(`${this.name}: timed out`)); }
      }, timeout);
    });
  }
  close() { this.ws.close(); }
}

test("cleanText strips control characters and limits length", () => {
  assert.equal(cleanText("  Mega\u0000\n  Man  ", 16), "Mega Man");
  assert.equal(cleanText("x".repeat(40), 16).length, 16);
  assert.equal(cleanText(42, 16), "");
});

test("lobby codes are unique and slots fill in order", () => {
  const registry = new LobbyRegistry();
  const host = { name: "Host" };
  const { lobby } = registry.create(host, { name: "Dig", isPublic: true });
  assert.match(lobby.code, /^[A-Z2-9]{5}$/);
  const guests = [1, 2, 3].map((n) => ({ name: `G${n}` }));
  for (const g of guests) assert.ok(registry.join(g, lobby.code.toLowerCase()).lobby);
  assert.deepEqual(guests.map((g) => g.slot), [2, 3, 4]);
  assert.equal(registry.join({ name: "Late" }, lobby.code).error, "full");
  registry.leave(guests[0]);
  const late = { name: "Late" };
  registry.join(late, lobby.code);
  assert.equal(late.slot, 2, "freed slot is reused");
});

test("serves the web build with isolation headers and compression", async () => {
  const res = await fetch(`http://127.0.0.1:${port}/`, { headers: { "accept-encoding": "gzip" } });
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cross-origin-opener-policy"), "same-origin");
  assert.equal(res.headers.get("cross-origin-embedder-policy"), "require-corp");
  assert.equal(res.headers.get("content-encoding"), "gzip");
  assert.match(await res.text(), /Relic Diver/);
  const wasm = await fetch(`http://127.0.0.1:${port}/index.wasm`);
  assert.equal(wasm.headers.get("content-type"), "application/wasm");
  const etag = wasm.headers.get("etag");
  const cached = await fetch(`http://127.0.0.1:${port}/index.wasm`, { headers: { "if-none-match": etag } });
  assert.equal(cached.status, 304);
  assert.equal((await fetch(`http://127.0.0.1:${port}/../server.js`)).status, 404);
  assert.equal((await fetch(`http://127.0.0.1:${port}/%2e%2e/server.js`)).status, 404);
  const invite = await fetch(`http://127.0.0.1:${port}/j/abcde`, { redirect: "manual" });
  assert.equal(invite.headers.get("location"), "/?lobby=ABCDE");
});

test("create, browse, join, relay and host departure", async () => {
  const host = await new Client("Volnutt").open();
  host.send({ t: "create", name: "Tidal Run", public: true });
  const joined = await host.next((m) => m.t === "joined");
  assert.equal(joined.slot, 1);
  const code = joined.code;

  const browser = await new Client("Browser").open();
  browser.send({ t: "list" });
  const list = await browser.next((m) => m.t === "lobbies");
  const listed = list.lobbies.find((l) => l.code === code);
  assert.ok(listed, "public lobby is listed");
  assert.equal(listed.host, "Volnutt");
  assert.equal(listed.players, 1);

  const guest = await new Client("Roll").open();
  guest.send({ t: "join", code });
  assert.equal((await guest.next((m) => m.t === "joined")).slot, 2);
  const entered = await host.next((m) => m.t === "entered");
  assert.equal(entered.name, "Roll");
  const roster = await guest.next((m) => m.t === "lobby" && m.lobby.players.length === 2);
  assert.deepEqual(roster.lobby.players.map((p) => p.name), ["Volnutt", "Roll"]);

  // Guest → host targeted packet arrives stamped with the guest's slot.
  guest.ws.send(Buffer.from([1, 9, 8, 7]));
  const packet = await host.next((m) => m.binary);
  assert.deepEqual([...packet.binary], [2, 9, 8, 7]);
  // Host broadcast reaches the guest but not the sender.
  host.ws.send(Buffer.from([0, 5]));
  assert.deepEqual([...(await guest.next((m) => m.binary)).binary], [1, 5]);

  host.send({ t: "status", state: "run", depth: 2 });
  const status = await guest.next((m) => m.t === "lobby" && m.lobby.state === "run");
  assert.equal(status.lobby.depth, 2);

  // Private lobbies are hidden from the browser but joinable by code.
  const secret = await new Client("Quiet").open();
  secret.send({ t: "create", name: "Hidden", public: false });
  const hiddenCode = (await secret.next((m) => m.t === "joined")).code;
  browser.send({ t: "list" });
  assert.ok(!(await browser.next((m) => m.t === "lobbies")).lobbies.some((l) => l.code === hiddenCode));
  browser.send({ t: "join", code: hiddenCode });
  assert.equal((await browser.next((m) => m.t === "joined")).slot, 2);

  host.close();
  const closed = await guest.next((m) => m.t === "closed");
  assert.equal(closed.reason, "host_left");
  browser.send({ t: "join", code: "ZZZZZ" });
  assert.equal((await browser.next((m) => m.t === "error")).code, "not_found");
  for (const c of [guest, browser, secret]) c.close();
});

test("guest departure notifies the host and frees the slot", async () => {
  const host = await new Client("Host").open();
  host.send({ t: "create", name: "Short Dig", public: true });
  const code = (await host.next((m) => m.t === "joined")).code;
  const guest = await new Client("Guest").open();
  guest.send({ t: "join", code });
  await guest.next((m) => m.t === "joined");
  guest.close();
  assert.equal((await host.next((m) => m.t === "left")).slot, 2);
  const roster = await host.next((m) => m.t === "lobby" && m.lobby.players.length === 1);
  assert.equal(roster.lobby.players[0].name, "Host");
  host.close();
});
