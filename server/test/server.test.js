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
  constructor(name, id = name.toLowerCase(), v = 2) {
    this.name = name;
    this.id = id;
    this.v = v;
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
    this.send({ t: "hello", name: this.name, id: this.id, v: this.v });
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

const member = (name) => ({ name, playerId: name, version: 2 });

test("lobby codes are unique and slots fill in order", () => {
  const registry = new LobbyRegistry();
  const host = member("Host");
  const { lobby } = registry.create(host, { name: "Dig", isPublic: true });
  assert.match(lobby.code, /^[A-Z2-9]{5}$/);
  const guests = [1, 2, 3].map((n) => member(`G${n}`));
  for (const g of guests) assert.ok(registry.join(g, lobby.code.toLowerCase()).lobby);
  assert.deepEqual(guests.map((g) => g.slot), [2, 3, 4]);
  assert.equal(registry.join(member("Late"), lobby.code).error, "full");
  registry.leave(guests[0]);
  const late = member("Late");
  registry.join(late, lobby.code);
  assert.equal(late.slot, 2, "freed slot is reused");
});

test("host role migrates, empty lobbies wait out a grace period", () => {
  let clock = 1000;
  const registry = new LobbyRegistry({ now: () => clock, runGraceMs: 60000, idleGraceMs: 5000 });
  const host = member("Host");
  const guest = member("Guest");
  const { lobby } = registry.create(host, { name: "Dig" });
  registry.join(guest, lobby.code);
  const left = registry.leave(host);
  assert.equal(left.newHost, 2, "remaining digger becomes host");
  assert.equal(lobby.hostSlot, 2);
  lobby.state = "run";
  registry.leave(guest);
  assert.ok(registry.lobbies.has(lobby.code), "empty lobby is kept");
  assert.equal(registry.publicList().length, 0, "empty lobbies are not listed");
  clock += 30000;
  const back = member("Host");
  const rejoin = registry.join(back, lobby.code);
  assert.equal(rejoin.takeover, true, "first digger back takes over hosting");
  assert.equal(lobby.hostSlot, back.slot);
  registry.leave(back);
  clock += 60001;
  registry.prune();
  assert.ok(!registry.lobbies.has(lobby.code), "lobby expires after the grace period");
});

test("same identity replaces its old connection", () => {
  const registry = new LobbyRegistry();
  const host = member("Host");
  const guest = member("Guest");
  const { lobby } = registry.create(host, { name: "Dig" });
  registry.join(guest, lobby.code);
  const again = member("Guest");
  const outcome = registry.join(again, lobby.code);
  assert.equal(outcome.replaced, guest);
  assert.equal(lobby.members.size, 2);
  assert.equal(again.slot, 2);
  // The host refreshing hands hosting to the live guest instead of starting fresh.
  const hostAgain = member("Host");
  const swap = registry.join(hostAgain, lobby.code);
  assert.equal(swap.replacedResult.newHost, 2);
  assert.equal(swap.takeover, false);
  assert.equal(lobby.hostSlot, 2);
});

test("kick, lock, password and version rules", () => {
  const registry = new LobbyRegistry();
  const host = member("Host");
  const { lobby } = registry.create(host, { name: "Dig", password: "relic" });
  assert.equal(registry.join(member("Pal"), lobby.code, "wrong").error, "password");
  const pal = member("Pal");
  assert.ok(registry.join(pal, lobby.code, "relic").lobby);
  assert.equal(registry.kick(pal, 1), null, "only the host can kick");
  assert.equal(registry.kick(host, pal.slot), pal);
  assert.equal(registry.join(member("Pal"), lobby.code, "relic").error, "banned");
  const friend = member("Friend");
  registry.join(friend, lobby.code, "relic");
  lobby.locked = true;
  assert.equal(registry.join(member("Stranger"), lobby.code, "relic").error, "locked");
  registry.leave(friend);
  assert.ok(registry.join(member("Friend"), lobby.code).lobby, "returning diggers skip lock and password");
  assert.equal(registry.join({ name: "Old", playerId: "old", version: 1 }, lobby.code).error, "version");
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

  // The host's checkpoint is stored; guests can't overwrite it.
  host.ws.send(Buffer.from([255, 1, 2, 3]));
  guest.ws.send(Buffer.from([255, 9, 9]));
  host.close();
  assert.equal((await guest.next((m) => m.t === "host")).slot, 2, "guest becomes host when the host leaves");
  guest.close();
  await new Promise((resolve) => setTimeout(resolve, 100));
  const returning = await new Client("Volnutt").open();
  returning.send({ t: "resume", code });
  const back = await returning.next((m) => m.t === "joined");
  assert.equal(back.takeover, true);
  assert.equal(back.checkpoint, true);
  assert.deepEqual([...(await returning.next((m) => m.binary)).binary], [255, 1, 2, 3], "returning digger receives the stored checkpoint");
  browser.send({ t: "join", code: "ZZZZZ" });
  assert.equal((await browser.next((m) => m.t === "error")).code, "not_found");
  for (const c of [returning, browser, secret]) c.close();
});

test("resume recreates a forgotten lobby under its old code", async () => {
  const digger = await new Client("Survivor").open();
  digger.send({ t: "resume", code: "K7QX2", name: "Survivor's Dig", public: false });
  const joined = await digger.next((m) => m.t === "joined");
  assert.equal(joined.code, "K7QX2");
  assert.equal(joined.recreated, true);
  assert.equal(joined.slot, 1);
  const old = await new Client("Old", "old", 1).open();
  old.send({ t: "join", code: "K7QX2" });
  assert.equal((await old.next((m) => m.t === "error")).code, "version");
  const refreshed = await new Client("Survivor").open();
  refreshed.send({ t: "join", code: "K7QX2" });
  await refreshed.next((m) => m.t === "joined");
  await digger.next((m) => m.t === "replaced");
  for (const c of [digger, old, refreshed]) c.close();
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
