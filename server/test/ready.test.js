// Lobby readiness and launch attempts (docs/handoff/QOL-READY-CONTRACT.md v1).
// Every timer runs on an injected clock, so nothing here waits real seconds.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { WebSocket } from "ws";
import { createServer } from "../server.js";
import { LobbyRegistry } from "../lobby.js";

function fakeClock() {
  let now = 1000;
  let nextHandle = 0;
  const pending = new Map();
  const callbacks = [];
  return {
    pending,
    callbacks,
    now: () => now,
    timers: {
      set(fn, ms) {
        const handle = ++nextHandle;
        pending.set(handle, { fn, at: now + ms });
        callbacks.push(fn);
        return handle;
      },
      clear(handle) { pending.delete(handle); },
    },
    advance(ms) {
      now += ms;
      for (const [handle, timer] of [...pending].sort((a, b) => a[1].at - b[1].at)) {
        if (timer.at > now || !pending.has(handle)) continue;
        pending.delete(handle);
        timer.fn();
      }
    },
  };
}

const digger = (n, extra = {}) => ({ name: `P${n}`, playerId: `p${n}`, version: 11, readyV1: true, ...extra });
const pick = (seq, extra = {}) => ({ t: "selection", seq, character: 0, weapon: 0, spec: "", buildRev: 0, ...extra });

function party(size = 2) {
  const clock = fakeClock();
  const events = [];
  let attempts = 0;
  const registry = new LobbyRegistry({ now: clock.now, timers: clock.timers, emit: (lobby, message) => events.push(message), changed: () => {}, newAttemptId: () => `att-${++attempts}` });
  const players = Array.from({ length: size }, (_, i) => digger(i + 1));
  const { lobby } = registry.create(players[0], { name: "Dig" });
  for (const p of players.slice(1)) registry.join(p, lobby.code);
  const ctx = {
    clock, events, registry, lobby, players,
    cmd: (p, message) => registry.readinessCommand(p, message),
    snap: () => registry.describe(lobby).readiness,
    member: (p) => registry.describe(lobby).players.find((m) => m.slot === p.slot),
    kinds: () => events.map((e) => e.t),
    ready: (p, ready = true) => registry.readinessCommand(p, { t: "ready", setupRev: ctx.snap().setupRev, ready }),
    readyAll() {
      ctx.players.forEach((p, i) => ctx.cmd(p, pick(1, { character: i % 4 })));
      // Everyone presses Ready against the same setupRev, as simultaneous presses would.
      const setupRev = ctx.snap().setupRev;
      for (const p of ctx.players) assert.deepEqual(ctx.cmd(p, { t: "ready", setupRev, ready: true }), { changed: true });
      return setupRev;
    },
    start: (seed = 4242, runId = "4242-1760600000-7") => registry.readinessCommand(ctx.players[0], { t: "start_request", setupRev: ctx.snap().setupRev, seed, runId }),
    prepared: (p) => registry.readinessCommand(p, { t: "launch_prepared", attemptId: ctx.snap().attemptId, setupRev: ctx.snap().setupRev }),
  };
  return ctx;
}

for (const size of [2, 4]) {
  test(`${size} diggers: all-ready waits for the host, countdown, prepare, one commit`, () => {
    const p = party(size);
    p.cmd(p.players[0], pick(1));
    assert.equal(p.snap().canStart, false, "nobody ready yet");
    const setupRev = p.readyAll();
    let s = p.snap();
    assert.equal(s.setupRev, setupRev, "another player's Ready never invalidates mine");
    assert.equal(s.canStart, true);
    assert.deepEqual(s.waitingSlots, []);
    p.clock.advance(60000);
    assert.equal(p.snap().phase, "idle", "all ready alone never starts");
    assert.deepEqual(p.events, []);

    assert.deepEqual(p.start(), { changed: true });
    s = p.snap();
    assert.equal(s.phase, "countdown");
    assert.equal(s.attemptId, "att-1");
    assert.equal(s.deadlineMs, p.clock.now() + 3000);
    assert.deepEqual(p.start(), { snapshot: true }, "an identical retry returns the current attempt");
    assert.deepEqual(p.cmd(p.players[0], { t: "start_request", setupRev, seed: 7, runId: "other" }), { error: "ready_attempt" });
    p.clock.advance(2999);
    assert.equal(p.snap().phase, "countdown");
    p.clock.advance(1);

    const slots = p.players.map((x) => x.slot);
    assert.deepEqual(p.events, [{ t: "launch_prepare", code: p.lobby.code, attemptId: "att-1", setupRev, hostSlot: 1, slots, seed: 4242, party: size, runId: "4242-1760600000-7", timeoutMs: 60000 }]);
    s = p.snap();
    assert.equal(s.phase, "preparing");
    assert.equal(s.deadlineMs, 0);
    assert.equal(s.prepareDeadlineMs, p.clock.now() + 60000);
    assert.deepEqual(s.waitingSlots, slots);

    for (const x of p.players.slice(0, -1)) {
      assert.deepEqual(p.prepared(x), { changed: true });
      assert.deepEqual(p.prepared(x), { snapshot: true }, "repeated prepared is idempotent");
    }
    assert.deepEqual(p.snap().waitingSlots, [slots.at(-1)], "still waiting for the slow digger");
    assert.equal(p.lobby.state, "lobby");
    const last = p.players.at(-1);
    assert.deepEqual(p.prepared(last), { changed: true });
    assert.equal(p.kinds().filter((t) => t === "launch_commit").length, 1);
    const commit = p.events.at(-1);
    assert.deepEqual(commit, { t: "launch_commit", code: p.lobby.code, attemptId: "att-1", setupRev, hostSlot: 1, slots, seed: 4242, party: size, runId: "4242-1760600000-7" });
    assert.equal(p.lobby.state, "run");
    s = p.snap();
    assert.equal(s.phase, "running");
    assert.equal(s.attemptId, "");

    // Retries and stragglers after the commit cannot launch again.
    assert.deepEqual(p.cmd(last, { t: "launch_prepared", attemptId: "att-1", setupRev }), { error: "ready_phase" });
    assert.deepEqual(p.start(), { error: "ready_phase" });
    p.clock.advance(120000);
    assert.equal(p.kinds().filter((t) => t === "launch_commit").length, 1);
    assert.equal(p.clock.pending.size, 0, "no timer outlives the commit");
  });
}

test("duplicate characters are allowed", () => {
  const p = party(4);
  for (const x of p.players) p.cmd(x, pick(1, { character: 2, spec: "spec_a" }));
  for (const x of p.players) p.ready(x);
  assert.equal(p.snap().canStart, true);
});

test("invalid shapes are rejected without coercion or state change", () => {
  const p = party(2);
  const [host, guest] = p.players;
  p.cmd(guest, pick(1));
  const before = p.snap().stateRev;
  const bad = [
    [guest, pick("2")], [guest, pick(0)], [guest, pick(2, { character: 4 })], [guest, pick(2, { weapon: -1 })],
    [guest, pick(2, { character: 1.5 })], [guest, pick(2, { spec: "spec_c" })], [guest, pick(2, { spec: null })],
    [guest, pick(2, { buildRev: -1 })], [guest, pick(2, { buildRev: "3" })],
    [guest, { t: "ready", setupRev: String(p.snap().setupRev), ready: true }], [guest, { t: "ready", setupRev: p.snap().setupRev, ready: "true" }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 0, runId: "a" }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 1000001, runId: "a" }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 2.5, runId: "a" }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 5, runId: "" }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 5, runId: "x".repeat(97) }],
    [host, { t: "start_request", setupRev: p.snap().setupRev, seed: 5, runId: "a\nb" }],
    [host, { t: "start_cancel", attemptId: 5 }],
    [guest, { t: "launch_failed", attemptId: "att-1", code: "boom" }],
    [guest, { t: "launch_prepared", attemptId: "", setupRev: 1 }],
  ];
  for (const [who, message] of bad) assert.deepEqual(p.cmd(who, message), { error: "ready_invalid" }, JSON.stringify(message));
  assert.equal(p.snap().stateRev, before);
  assert.deepEqual(p.events, []);
});

test("start needs the host, everyone ready, a published loadout and the current setup", () => {
  const p = party(3);
  const [host, guest, third] = p.players;
  assert.deepEqual(p.ready(guest), { error: "ready_selection_required" });
  p.readyAll();
  assert.deepEqual(p.cmd(guest, { t: "start_request", setupRev: p.snap().setupRev, seed: 1, runId: "r" }), { error: "ready_not_host" });
  p.ready(third, false);
  const s = p.snap();
  assert.deepEqual(s.waitingSlots, [third.slot]);
  assert.equal(s.canStart, false);
  assert.deepEqual(p.start(), { error: "ready_waiting" });
  assert.deepEqual(p.cmd(third, { t: "ready", setupRev: s.setupRev - 1, ready: true }), { error: "ready_stale" });
  p.ready(third);
  assert.deepEqual(p.cmd(host, { t: "start_request", setupRev: s.setupRev - 1, seed: 1, runId: "r" }), { error: "ready_stale" });
  assert.deepEqual(p.ready(third), { snapshot: true }, "duplicate Ready is a no-op");
  assert.deepEqual(p.start(), { changed: true });
});

test("selection and build changes reset consent; seq orders loadout updates", () => {
  const p = party(2);
  const [host, guest] = p.players;
  const setupRev = p.readyAll();
  // Same content under a newer seq acknowledges without resetting anyone.
  assert.deepEqual(p.cmd(guest, pick(2, { character: 1 })), { changed: true });
  assert.equal(p.snap().setupRev, setupRev);
  assert.equal(p.member(guest).selection.seq, 2);
  assert.deepEqual(p.cmd(guest, pick(1, { character: 3 })), { snapshot: true }, "older seq is ignored");
  assert.equal(p.member(guest).selection.character, 1);
  assert.deepEqual(p.cmd(guest, pick(2, { character: 3 })), { error: "ready_invalid" }, "same seq, different content");
  // A Workshop purchase changes only buildRev; it still needs fresh consent from everyone.
  assert.deepEqual(p.cmd(guest, pick(3, { character: 1, buildRev: 1 })), { changed: true });
  assert.equal(p.snap().setupRev, setupRev + 1);
  assert.equal(p.member(host).ready, false);
  assert.equal(p.member(guest).ready, false);
  assert.deepEqual(p.member(guest).selection, { seq: 3, character: 1, weapon: 0, spec: "", buildRev: 1 });

  for (const x of p.players) p.ready(x);
  p.start();
  p.cmd(host, pick(2, { spec: "spec_b" }));
  assert.deepEqual(p.events.at(-1), { t: "launch_aborted", code: p.lobby.code, attemptId: "att-1", reason: "selection" });
  assert.equal(p.snap().phase, "idle");
  assert.equal(p.member(guest).ready, false);
});

test("unready and host Cancel stop the countdown; late timers do nothing", () => {
  const p = party(2);
  const [host, guest] = p.players;
  const setupRev = p.readyAll();
  p.start();
  const countdownTimer = p.clock.callbacks.at(-1);
  p.ready(guest, false);
  assert.deepEqual(p.events.at(-1), { t: "launch_aborted", code: p.lobby.code, attemptId: "att-1", reason: "unready" });
  let s = p.snap();
  assert.equal(s.phase, "idle");
  assert.equal(s.setupRev, setupRev, "an unready keeps the setup");
  assert.equal(p.member(host).ready, true, "and the others' consent");
  countdownTimer();
  p.clock.advance(5000);
  assert.equal(p.snap().phase, "idle");
  assert.equal(p.events.length, 1, "the canceled countdown never prepares");
  assert.deepEqual(p.cmd(guest, { t: "launch_prepared", attemptId: "att-1", setupRev }), { error: "ready_attempt" });

  p.ready(guest);
  p.start();
  assert.equal(p.snap().attemptId, "att-2");
  assert.deepEqual(p.cmd(guest, { t: "start_cancel", attemptId: "att-2" }), { error: "ready_not_host" });
  assert.deepEqual(p.cmd(host, { t: "start_cancel", attemptId: "att-1" }), { error: "ready_attempt" });
  assert.deepEqual(p.cmd(host, { t: "start_cancel", attemptId: "att-2" }), { changed: true });
  assert.equal(p.events.at(-1).reason, "cancel");
  s = p.snap();
  assert.equal(s.setupRev, setupRev + 1, "host Cancel makes the next attempt deliberate");
  assert.deepEqual(s.waitingSlots, [host.slot, guest.slot]);
  assert.deepEqual(p.cmd(host, { t: "start_cancel", attemptId: "att-2" }), { error: "ready_phase" });
  assert.equal(p.clock.pending.size, 0);
});

test("prepared before the countdown ends or with a stale setup is refused", () => {
  const p = party(2);
  const [, guest] = p.players;
  const setupRev = p.readyAll();
  p.start();
  assert.deepEqual(p.cmd(guest, { t: "launch_prepared", attemptId: "att-1", setupRev }), { error: "ready_phase" });
  p.clock.advance(3000);
  assert.deepEqual(p.cmd(guest, { t: "launch_prepared", attemptId: "att-1", setupRev: setupRev - 1 }), { error: "ready_stale" });
  assert.deepEqual(p.cmd(guest, { t: "launch_prepared", attemptId: "att-9", setupRev }), { error: "ready_attempt" });
  assert.equal(p.snap().phase, "preparing");
});

const rosterCases = [
  ["a late join", "countdown", (p) => p.registry.join(digger(9), p.lobby.code), "roster"],
  ["a late join", "preparing", (p) => p.registry.join(digger(9), p.lobby.code), "roster"],
  ["a guest disconnect", "countdown", (p) => p.registry.leave(p.players[1]), "disconnect"],
  ["a guest disconnect", "preparing", (p) => p.registry.leave(p.players[1]), "disconnect"],
  ["the host leaving", "countdown", (p) => p.registry.leave(p.players[0]), "host"],
  ["the host leaving", "preparing", (p) => p.registry.leave(p.players[0]), "host"],
  ["a kick", "countdown", (p) => p.registry.kick(p.players[0], p.players[2].slot), "roster"],
  ["a kick", "preparing", (p) => p.registry.kick(p.players[0], p.players[2].slot), "roster"],
  ["a replaced connection", "countdown", (p) => p.registry.join(digger(2), p.lobby.code), "roster"],
  ["a replaced connection", "preparing", (p) => p.registry.join(digger(2), p.lobby.code), "roster"],
];
for (const [label, phase, change, reason] of rosterCases) {
  test(`${label} during ${phase} aborts and requires fresh consent`, () => {
    const p = party(3);
    const setupRev = p.readyAll();
    p.start();
    if (phase === "preparing") {
      p.clock.advance(3000);
      p.prepared(p.players[0]);
    }
    const prior = p.events.length;
    change(p);
    const aborted = p.events.slice(prior);
    assert.deepEqual(aborted, [{ t: "launch_aborted", code: p.lobby.code, attemptId: "att-1", reason }]);
    const s = p.snap();
    assert.equal(s.phase, "idle");
    assert.ok(s.setupRev > setupRev);
    assert.equal(s.canStart, false);
    assert.ok(p.registry.describe(p.lobby).players.every((m) => !m.ready), "nobody's old consent survives");
    assert.equal(p.clock.pending.size, 0);
    p.clock.advance(120000);
    assert.equal(p.events.length, prior + 1, "no late prepare/commit/timeout");
    assert.equal(p.lobby.state, "lobby");
  });
}

test("host migration in the lobby gives the new host the Start", () => {
  const p = party(3);
  p.readyAll();
  p.registry.leave(p.players[0]);
  const [, guest, third] = p.players;
  assert.equal(p.lobby.hostSlot, guest.slot);
  for (const x of [guest, third]) p.ready(x);
  assert.deepEqual(p.cmd(guest, { t: "start_request", setupRev: p.snap().setupRev, seed: 9, runId: "r9" }), { changed: true });
  p.clock.advance(3000);
  assert.deepEqual(p.events.at(-1).slots, [guest.slot, third.slot]);
  assert.equal(p.events.at(-1).hostSlot, guest.slot);
});

test("preparation failure and timeout leave a usable lobby", () => {
  const p = party(2);
  const [host, guest] = p.players;
  const setupRev = p.readyAll();
  p.start();
  p.clock.advance(3000);
  assert.deepEqual(p.cmd(guest, { t: "launch_failed", attemptId: "att-1", code: "account" }), { changed: true });
  assert.deepEqual(p.events.at(-1), { t: "launch_aborted", code: p.lobby.code, attemptId: "att-1", reason: "preparation_failed" });
  assert.equal(p.snap().setupRev, setupRev + 1);
  assert.equal(p.member(host).ready, false);

  for (const x of p.players) p.ready(x);
  p.start();
  p.clock.advance(3000);
  p.prepared(host);
  p.clock.advance(59999);
  assert.equal(p.snap().phase, "preparing");
  p.clock.advance(1);
  assert.deepEqual(p.events.at(-1), { t: "launch_aborted", code: p.lobby.code, attemptId: "att-2", reason: "preparation_timeout" });
  const s = p.snap();
  assert.equal(s.phase, "idle");
  assert.equal(s.prepareDeadlineMs, 0);
  assert.deepEqual(p.cmd(guest, { t: "launch_prepared", attemptId: "att-2", setupRev: s.setupRev - 1 }), { error: "ready_attempt" });
  assert.equal(p.lobby.state, "lobby");
  // The lobby still works: ready again and launch.
  for (const x of p.players) p.ready(x);
  p.start();
  p.clock.advance(3000);
  for (const x of p.players) p.prepared(x);
  assert.equal(p.events.at(-1).t, "launch_commit");
  assert.equal(p.events.at(-1).attemptId, "att-3");
});

test("run status cannot launch a fresh dig; recovery and routine reports still work", () => {
  const p = party(2);
  const [host, guest] = p.players;
  p.readyAll();
  assert.equal(p.registry.reportStatus(host, "run", 1), false, "status run is not a launch authorization");
  assert.equal(p.lobby.state, "lobby");
  p.start();
  assert.equal(p.registry.reportStatus(host, "run", 1), false);
  p.clock.advance(3000);
  assert.equal(p.registry.reportStatus(host, "run", 1), false, "nor while preparing");
  for (const x of p.players) p.prepared(x);
  assert.equal(p.lobby.state, "run");

  // Descents, migration and rejoin during the dig never touch launch consent.
  p.lobby.checkpoint = Buffer.from([1, 2, 3]);
  assert.equal(p.registry.reportStatus(host, "run", 2), true);
  assert.equal(p.lobby.depth, 2);
  const events = p.events.length;
  p.registry.leave(host);
  assert.equal(p.lobby.hostSlot, guest.slot);
  assert.equal(p.registry.reportStatus(guest, "run", 2), true, "the migrated host keeps reporting the run");
  const back = digger(1);
  assert.equal(p.registry.join(back, p.lobby.code).takeover, false);
  p.registry.leave(guest);
  p.registry.leave(back);
  const returning = digger(2);
  assert.equal(p.registry.join(returning, p.lobby.code).takeover, true, "an emptied running lobby is still taken over");
  assert.deepEqual([...p.lobby.checkpoint], [1, 2, 3], "with its checkpoint");
  assert.equal(p.snap().phase, "running");
  assert.equal(p.events.length, events, "no aborts or launches during the dig");

  // Finishing the dig returns everyone to an idle lobby that needs fresh Ready.
  const setupRev = p.snap().setupRev;
  p.cmd(returning, pick(1));
  assert.equal(p.registry.reportStatus(returning, "lobby", 3), true);
  const s = p.snap();
  assert.equal(s.phase, "idle");
  assert.ok(s.setupRev > setupRev);
  assert.equal(p.member(returning).ready, false);
  assert.ok(p.member(returning).selection, "the loadout is kept");
  assert.equal(p.lobby.checkpoint, null);
});

test("a resumed or taken-over connection can restore its dig without fresh consent", () => {
  const p = party(1);
  const [host] = p.players;
  host.recovery = true; // set by the server for resume/takeover entries
  assert.equal(p.registry.reportStatus(host, "run", 2), true);
  assert.equal(p.lobby.state, "run");
  assert.equal(p.snap().phase, "running");
  assert.equal(host.recovery, false, "used once");

  const q = party(1);
  q.players[0].recovery = true;
  q.cmd(q.players[0], pick(1));
  q.ready(q.players[0]);
  assert.equal(q.registry.reportStatus(q.players[0], "run", 1), false, "readying for a fresh dig gives up the recovery path");
});

test("readiness and legacy members never share a lobby", () => {
  const registry = new LobbyRegistry();
  const legacy = { name: "Old", playerId: "old", version: 11 };
  const { lobby: old } = registry.create(legacy, { name: "Old" });
  assert.equal(old.readiness, null);
  assert.equal(registry.describe(old).readiness, undefined);
  assert.equal(registry.join(digger(2), old.code).error, "ready_feature");
  assert.deepEqual(registry.readinessCommand(legacy, pick(1)), { error: "ready_feature" });
  assert.equal(registry.reportStatus(legacy, "run", 1), true, "legacy lobbies keep the old status semantics");
  const { lobby: fresh } = registry.create(digger(3), { name: "New" });
  assert.equal(registry.join({ name: "Old2", playerId: "old2", version: 11 }, fresh.code).error, "ready_feature");
  assert.deepEqual(registry.readinessCommand({ lobby: null }, pick(1)), { error: "ready_phase" });
});

test("disposing or pruning a lobby clears its timers", () => {
  const p = party(2);
  p.readyAll();
  p.start();
  assert.equal(p.clock.pending.size, 1);
  p.registry.dispose();
  assert.equal(p.clock.pending.size, 0);
});

// ---- Relay over real sockets on a disposable port ---------------------------

let app;
let port;
let webRoot;
let clock;

before(async () => {
  clock = fakeClock();
  webRoot = fs.mkdtempSync(path.join(os.tmpdir(), "relic-ready-"));
  fs.writeFileSync(path.join(webRoot, "index.html"), "<!doctype html>");
  app = createServer({ port: 0, webRoot, log: () => {}, readiness: { now: clock.now, timers: clock.timers } });
  port = await app.listen();
});

after(async () => {
  await app.close();
  assert.equal(clock.pending.size, 0, "closing the server clears launch timers");
  fs.rmSync(webRoot, { recursive: true, force: true });
});

class Client {
  constructor(name, { id = name.toLowerCase(), v = 11, features = ["ready_v1"] } = {}) {
    Object.assign(this, { name, id, v, features, queue: [], waiters: [] });
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
    const hello = { t: "hello", name: this.name, id: this.id, v: this.v };
    if (this.features) hello.features = this.features;
    this.send(hello);
    this.welcome = await this.next((m) => m.t === "welcome");
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
  // The newest snapshot satisfying `match`.
  snapshot(match = () => true) { return this.next((m) => m.t === "lobby" && m.lobby.readiness && match(m.lobby)); }
  close() { this.ws.close(); }
}

test("two clients ready, start and commit over the relay", async () => {
  const host = await new Client("Volnutt").open();
  assert.deepEqual(host.welcome.features, ["ready_v1"]);
  host.send({ t: "create", name: "Ready Dig", public: false });
  const code = (await host.next((m) => m.t === "joined")).code;
  const guest = await new Client("Roll").open();
  guest.send({ t: "join", code });
  await guest.next((m) => m.t === "joined");
  host.send(pick(1));
  guest.send(pick(1, { character: 1 }));
  const both = await host.snapshot((l) => l.players.length === 2 && l.players.every((x) => x.selection));
  const setupRev = both.lobby.readiness.setupRev;
  assert.equal(both.lobby.readiness.v, 1);

  // A guest can't start, and gets a typed error plus its current state.
  guest.send({ t: "start_request", setupRev, seed: 77, runId: "77-1-1" });
  assert.deepEqual(await guest.next((m) => m.t === "ready_error"), { t: "ready_error", code: "ready_not_host", setupRev });
  host.send({ t: "start_request", setupRev, seed: 77, runId: "77-1-1" });
  assert.equal((await host.next((m) => m.t === "ready_error")).code, "ready_waiting");

  host.send({ t: "ready", setupRev, ready: true });
  guest.send({ t: "ready", setupRev, ready: true });
  await host.snapshot((l) => l.readiness.canStart);
  // Status run from an idle readiness lobby is ignored.
  host.send({ t: "status", state: "run", depth: 1 });
  host.send({ t: "start_request", setupRev, seed: 77, runId: "77-1-1" });
  const counting = await guest.snapshot((l) => l.readiness.phase === "countdown");
  assert.equal(counting.lobby.state, "lobby");
  clock.advance(3000);
  const prepare = await guest.next((m) => m.t === "launch_prepare");
  assert.deepEqual(prepare, { t: "launch_prepare", code, attemptId: counting.lobby.readiness.attemptId, setupRev, hostSlot: 1, slots: [1, 2], seed: 77, party: 2, runId: "77-1-1", timeoutMs: 60000 });
  for (const c of [host, guest]) c.send({ t: "launch_prepared", attemptId: prepare.attemptId, setupRev });
  const commits = await Promise.all([host, guest].map((c) => c.next((m) => m.t === "launch_commit")));
  const { timeoutMs, ...launch } = prepare;
  assert.equal(timeoutMs, 60000);
  for (const commit of commits) assert.deepEqual(commit, { ...launch, t: "launch_commit" }, "everyone commits the same seed and party");
  const running = await guest.snapshot((l) => l.readiness.phase === "running");
  assert.equal(running.lobby.state, "run");
  host.send({ t: "launch_prepared", attemptId: prepare.attemptId, setupRev });
  assert.equal((await host.next((m) => m.t === "ready_error")).code, "ready_phase");
  host.close();
  guest.close();
});

test("relay keeps legacy and readiness clients apart; resume can recover a run", async () => {
  const old = await new Client("Old", { features: null }).open();
  assert.deepEqual(old.welcome.features, ["ready_v1"], "the server always advertises what it supports");
  old.send({ t: "create", name: "Legacy" });
  const legacyCode = (await old.next((m) => m.t === "joined")).code;
  old.send(pick(1));
  assert.equal((await old.next((m) => m.t === "ready_error")).code, "ready_feature");
  const modern = await new Client("Modern").open();
  modern.send({ t: "join", code: legacyCode });
  assert.equal((await modern.next((m) => m.t === "error")).code, "ready_feature");

  // A digger returning to a lobby the server forgot restores its dig.
  modern.send({ t: "resume", code: "R7QX2", name: "Back", public: false });
  assert.equal((await modern.next((m) => m.t === "joined")).recreated, true);
  modern.send({ t: "status", state: "run", depth: 2 });
  const resumed = await modern.snapshot((l) => l.state === "run");
  assert.equal(resumed.lobby.readiness.phase, "running");
  assert.equal(resumed.lobby.depth, 2);
  old.close();
  modern.close();
});

test("a countdown pending at shutdown is cleared by close", async () => {
  const host = await new Client("Solo").open();
  host.send({ t: "create", name: "Solo" });
  await host.next((m) => m.t === "joined");
  host.send(pick(1));
  const { lobby } = await host.snapshot((l) => l.players[0].selection);
  host.send({ t: "ready", setupRev: lobby.readiness.setupRev, ready: true });
  await host.snapshot((l) => l.readiness.canStart);
  host.send({ t: "start_request", setupRev: lobby.readiness.setupRev, seed: 5, runId: "solo" });
  await host.snapshot((l) => l.readiness.phase === "countdown");
  assert.ok(clock.pending.size >= 1);
  // `after` closes the server and asserts the timer is gone.
});
