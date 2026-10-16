// Lobby bookkeeping and packet relay for Relic Diver co-op.
//
// Text frames carry small JSON lobby commands. Binary frames carry game
// packets the server never inspects: a client sends [target][payload]
// (target 0 = every other member) and members receive [source][payload].
// Target 255 from the host stores an opaque run checkpoint on the server.
//
// Runs survive people leaving: when the host goes, the lowest remaining slot
// becomes host. An empty lobby is kept for a grace period so anyone returning
// (refresh, crash, lost Wi-Fi) can pick the dig back up from its checkpoint.
//
// Lobbies created by clients that announce the "ready_v1" feature also track
// readiness (docs/handoff/QOL-READY-CONTRACT.md v1): everyone publishes a
// loadout and readies, the host asks to start, a short countdown runs, every
// frozen participant prepares, then exactly one launch_commit begins the dig.
// The relay owns that state because it can't read the binary M_START packet.

import { randomUUID } from "node:crypto";

export const MAX_PLAYERS = 4;
export const CHECKPOINT_TARGET = 255;
export const READY_FEATURE = "ready_v1";
export const READY_COMMANDS = new Set(["selection", "ready", "start_request", "start_cancel", "launch_prepared", "launch_failed"]);
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 5;
const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{5}$/;
const SPECS = new Set(["", "spec_a", "spec_b"]);
const FAILURE_CODES = new Set(["account", "storage", "load", "cancel"]);
const RUN_ID_PATTERN = /^[\x20-\x7e]{1,96}$/;
const MAX_SEED = 1000000;

export function cleanText(value, max) {
  if (typeof value !== "string") return "";
  // Drop control characters and collapse whitespace so names render safely in the HUD.
  return value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").replace(/\s+/g, " ").trim().slice(0, max);
}

export function cleanCode(value) {
  return cleanText(value, 12).toUpperCase();
}

const count = (value, min) => Number.isSafeInteger(value) && value >= min;
const index = (value) => Number.isInteger(value) && value >= 0 && value <= 3;
const attemptText = (value) => typeof value === "string" && value.length > 0 && value.length <= 64;
const sameSelection = (a, b) => a.character === b.character && a.weapon === b.weapon && a.spec === b.spec && a.buildRev === b.buildRev;

const defaultTimers = {
  set(fn, ms) {
    const handle = setTimeout(fn, ms);
    handle.unref?.();
    return handle;
  },
  clear: (handle) => clearTimeout(handle),
};

export class LobbyRegistry {
  constructor({ maxLobbies = 200, random = Math.random, runGraceMs = 15 * 60 * 1000, idleGraceMs = 3 * 60 * 1000, now = Date.now, timers = defaultTimers, countdownMs = 3000, prepareTimeoutMs = 60000, newAttemptId = randomUUID, emit = () => {}, changed = () => {} } = {}) {
    this.maxLobbies = maxLobbies;
    this.random = random;
    this.runGraceMs = runGraceMs;
    this.idleGraceMs = idleGraceMs;
    this.now = now;
    this.timers = timers;
    this.countdownMs = countdownMs;
    this.prepareTimeoutMs = prepareTimeoutMs;
    this.newAttemptId = newAttemptId;
    // emit(lobby, message) sends a launch lifecycle message to every member;
    // changed(lobby) publishes a fresh snapshot after a timer moved the state.
    this.emit = emit;
    this.changed = changed;
    this.lobbies = new Map();
  }

  newCode() {
    for (let attempt = 0; attempt < 1000; attempt++) {
      let code = "";
      for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[Math.floor(this.random() * CODE_ALPHABET.length)];
      if (!this.lobbies.has(code)) return code;
    }
    throw new Error("Could not allocate a lobby code");
  }

  // `code` lets a returning player recreate their lobby after a server restart.
  create(client, { name, isPublic, password, code }) {
    this.prune();
    if (this.lobbies.size >= this.maxLobbies) return { error: "server_full" };
    const wanted = cleanCode(code);
    const lobby = {
      code: CODE_PATTERN.test(wanted) && !this.lobbies.has(wanted) ? wanted : this.newCode(),
      name: cleanText(name, 28) || `${client.name}'s Dig`,
      isPublic: isPublic !== false,
      password: cleanText(password, 24),
      locked: false,
      version: client.version,
      state: "lobby",
      depth: 1,
      created: this.now(),
      members: new Map(),
      hostSlot: 1,
      knownIds: new Set(),
      banned: new Set(),
      checkpoint: null,
      emptySince: null,
      // Legacy lobbies (creator without ready_v1) keep the old ungated start.
      readiness: client.readyV1 ? { setupRev: 1, stateRev: 1, phase: "idle", attempt: null, members: new Map() } : null,
    };
    this.lobbies.set(lobby.code, lobby);
    this.addMember(lobby, client, 1);
    return { lobby, takeover: false };
  }

  join(client, code, password) {
    this.prune();
    const lobby = this.lobbies.get(cleanCode(code));
    if (!lobby) return { error: "not_found" };
    if (lobby.version !== client.version) return { error: "version" };
    // Readiness and legacy members never share a lobby.
    if (Boolean(lobby.readiness) !== Boolean(client.readyV1)) return { error: "ready_feature" };
    if (lobby.banned.has(client.playerId)) return { error: "banned" };
    const returning = lobby.knownIds.has(client.playerId);
    // A second connection with the same identity (refresh, duplicate tab) replaces the first.
    const previous = [...lobby.members.values()].find((m) => m.playerId === client.playerId);
    if (!returning) {
      if (lobby.locked) return { error: "locked" };
      if (lobby.password && cleanText(password, 24) !== lobby.password) return { error: "password" };
    }
    if (!previous && lobby.members.size >= MAX_PLAYERS) return { error: "full" };
    // A late arrival aborts any launch in flight before it can see it.
    const replaced = previous ? this.leave(previous, "roster") : (this.invalidate(lobby, "roster"), null);
    let slot = 1;
    while (lobby.members.has(slot)) slot++;
    const takeover = lobby.members.size === 0;
    this.addMember(lobby, client, slot);
    if (takeover) lobby.hostSlot = slot;
    return { lobby, takeover, replaced: previous || null, replacedResult: replaced };
  }

  addMember(lobby, client, slot) {
    client.lobby = lobby;
    client.slot = slot;
    client.recovery = false;
    lobby.members.set(slot, client);
    lobby.knownIds.add(client.playerId);
    lobby.emptySince = null;
    lobby.readiness?.members.set(client, { ready: false, selection: null });
  }

  // Removes a member. Returns { lobby, slot, newHost } where newHost is set when the host role moved.
  // `reason` labels an aborted launch; by default a departing host is "host", anyone else "disconnect".
  leave(client, reason) {
    const lobby = client.lobby;
    if (!lobby) return null;
    const slot = client.slot;
    const wasHost = lobby.hostSlot === slot;
    lobby.members.delete(slot);
    lobby.readiness?.members.delete(client);
    client.lobby = null;
    client.slot = 0;
    client.recovery = false;
    let newHost = 0;
    if (lobby.members.size === 0) lobby.emptySince = this.now();
    else if (wasHost) {
      lobby.hostSlot = Math.min(...lobby.members.keys());
      newHost = lobby.hostSlot;
    }
    this.invalidate(lobby, reason || (wasHost ? "host" : "disconnect"));
    return { lobby, slot, newHost };
  }

  kick(host, slot) {
    const lobby = host.lobby;
    if (!lobby || host.slot !== lobby.hostSlot || slot === host.slot) return null;
    const target = lobby.members.get(slot);
    if (!target) return null;
    lobby.banned.add(target.playerId);
    lobby.knownIds.delete(target.playerId);
    this.leave(target, "roster");
    return target;
  }

  // Forget empty lobbies whose grace period ran out.
  prune() {
    const now = this.now();
    for (const [code, lobby] of this.lobbies) {
      if (lobby.emptySince === null) continue;
      const grace = lobby.state === "run" ? this.runGraceMs : this.idleGraceMs;
      if (now - lobby.emptySince >= grace) {
        this.dropAttempt(lobby);
        this.lobbies.delete(code);
      }
    }
  }

  // Stop every pending countdown/preparation timer (server shutdown).
  dispose() {
    for (const lobby of this.lobbies.values()) this.dropAttempt(lobby);
  }

  publicList() {
    this.prune();
    const list = [];
    for (const lobby of this.lobbies.values()) {
      if (!lobby.isPublic || lobby.members.size === 0) continue;
      list.push(this.summary(lobby));
    }
    list.sort((a, b) => b.created - a.created);
    return list.slice(0, 50);
  }

  summary(lobby) {
    const host = lobby.members.get(lobby.hostSlot);
    return {
      code: lobby.code,
      name: lobby.name,
      host: host ? host.name : "",
      players: lobby.members.size,
      max: MAX_PLAYERS,
      state: lobby.state,
      depth: lobby.depth,
      locked: lobby.locked,
      password: lobby.password !== "",
      created: lobby.created,
    };
  }

  describe(lobby) {
    const r = lobby.readiness;
    const players = [];
    for (const [slot, member] of [...lobby.members.entries()].sort((a, b) => a[0] - b[0])) {
      const player = { slot, name: member.name, id: member.playerId };
      if (r) {
        const state = r.members.get(member);
        player.ready = Boolean(state?.ready);
        if (state?.selection) player.selection = { ...state.selection };
      }
      players.push(player);
    }
    const description = { ...this.summary(lobby), isPublic: lobby.isPublic, hostSlot: lobby.hostSlot, players };
    if (r) description.readiness = this.readinessSnapshot(lobby);
    return description;
  }

  readinessSnapshot(lobby) {
    const r = lobby.readiness;
    const a = r.attempt;
    const slots = [...lobby.members.keys()].sort((x, y) => x - y);
    let waitingSlots = [];
    if (r.phase === "idle") waitingSlots = slots.filter((slot) => !r.members.get(lobby.members.get(slot))?.ready);
    else if (r.phase === "preparing") waitingSlots = [...a.participants.keys()].filter((slot) => !a.prepared.has(slot)).sort((x, y) => x - y);
    return {
      v: 1,
      setupRev: r.setupRev,
      stateRev: r.stateRev,
      phase: r.phase,
      attemptId: a ? a.id : "",
      deadlineMs: r.phase === "countdown" ? a.deadlineMs : 0,
      prepareDeadlineMs: r.phase === "preparing" ? a.prepareDeadlineMs : 0,
      waitingSlots,
      canStart: r.phase === "idle" && lobby.members.has(lobby.hostSlot) && slots.length > 0 && waitingSlots.length === 0,
    };
  }

  // ---- Readiness -----------------------------------------------------------

  // A roster/host/selection change: abort any launch in flight and require
  // fresh consent. A running dig only records the change; its own recovery
  // and host migration carry on untouched.
  invalidate(lobby, reason) {
    const r = lobby.readiness;
    if (!r) return;
    if (r.attempt) return this.abort(lobby, reason);
    if (r.phase === "idle") this.resetConsent(lobby);
    r.stateRev++;
  }

  resetConsent(lobby) {
    const r = lobby.readiness;
    r.setupRev++;
    for (const state of r.members.values()) state.ready = false;
  }

  dropAttempt(lobby) {
    const a = lobby.readiness?.attempt;
    if (!a) return null;
    if (a.timer) this.timers.clear(a.timer);
    a.timer = null;
    lobby.readiness.attempt = null;
    return a;
  }

  // Cancel the current attempt. An unready keeps everyone else's consent; every
  // other reason (cancel, failure, timeout, roster, selection, host) resets it.
  abort(lobby, reason) {
    const r = lobby.readiness;
    const a = this.dropAttempt(lobby);
    if (!a) return;
    r.phase = "idle";
    if (reason !== "unready") this.resetConsent(lobby);
    r.stateRev++;
    this.emit(lobby, { t: "launch_aborted", code: lobby.code, attemptId: a.id, reason });
  }

  // The frozen party still matches the lobby exactly and everyone still consents.
  attemptIntact(lobby, a) {
    const r = lobby.readiness;
    if (r.setupRev !== a.setupRev || lobby.hostSlot !== a.hostSlot || lobby.members.get(a.hostSlot) !== a.host) return false;
    if (lobby.members.size !== a.participants.size) return false;
    for (const [slot, member] of a.participants) {
      if (lobby.members.get(slot) !== member || !r.members.get(member)?.ready) return false;
    }
    return true;
  }

  // Timer callbacks re-check that they still belong to the live attempt.
  current(lobby, a, phase) {
    return this.lobbies.get(lobby.code) === lobby && lobby.readiness?.attempt === a && lobby.readiness.phase === phase;
  }

  launchPayload(lobby, a) {
    return { code: lobby.code, attemptId: a.id, setupRev: a.setupRev, hostSlot: a.hostSlot, slots: [...a.participants.keys()].sort((x, y) => x - y), seed: a.seed, party: a.party, runId: a.runId };
  }

  countdownElapsed(lobby, a) {
    if (!this.current(lobby, a, "countdown")) return;
    a.timer = null;
    if (!this.attemptIntact(lobby, a)) {
      this.abort(lobby, "roster");
      return this.changed(lobby);
    }
    const r = lobby.readiness;
    r.phase = "preparing";
    a.prepareDeadlineMs = this.now() + this.prepareTimeoutMs;
    a.timer = this.timers.set(() => this.prepareExpired(lobby, a), this.prepareTimeoutMs);
    r.stateRev++;
    this.emit(lobby, { t: "launch_prepare", ...this.launchPayload(lobby, a), timeoutMs: this.prepareTimeoutMs });
    this.changed(lobby);
  }

  prepareExpired(lobby, a) {
    if (!this.current(lobby, a, "preparing")) return;
    a.timer = null;
    this.abort(lobby, "preparation_timeout");
    this.changed(lobby);
  }

  commit(lobby, a) {
    const r = lobby.readiness;
    if (!this.attemptIntact(lobby, a)) return this.abort(lobby, "roster");
    this.dropAttempt(lobby);
    r.phase = "running";
    for (const state of r.members.values()) state.ready = false;
    r.stateRev++;
    lobby.state = "run";
    lobby.depth = 1;
    // The previous dig's checkpoint must never be offered as this run's takeover copy.
    lobby.checkpoint = null;
    this.emit(lobby, { t: "launch_commit", ...this.launchPayload(lobby, a) });
  }

  // Handles one readiness command. Returns { error } for a ready_error reply,
  // { snapshot: true } when only the sender needs the current state, or
  // { changed: true } when every member needs a new snapshot.
  readinessCommand(client, message) {
    const lobby = client.lobby;
    if (!lobby) return { error: "ready_phase" };
    const r = lobby.readiness;
    if (!r || !client.readyV1) return { error: "ready_feature" };
    const mine = r.members.get(client);
    const isHost = client.slot === lobby.hostSlot;
    const a = r.attempt;
    switch (message.t) {
      case "selection": {
        const { seq, character, weapon, spec, buildRev } = message;
        if (!count(seq, 1) || !index(character) || !index(weapon) || typeof spec !== "string" || !SPECS.has(spec) || !count(buildRev, 0)) return { error: "ready_invalid" };
        const next = { seq, character, weapon, spec, buildRev };
        const prior = mine.selection;
        if (prior && seq < prior.seq) return { snapshot: true };
        if (prior && seq === prior.seq) return sameSelection(prior, next) ? { snapshot: true } : { error: "ready_invalid" };
        mine.selection = next;
        if (prior && sameSelection(prior, next)) r.stateRev++;
        else this.invalidate(lobby, "selection");
        return { changed: true };
      }
      case "ready": {
        if (!count(message.setupRev, 1) || typeof message.ready !== "boolean") return { error: "ready_invalid" };
        if (r.phase === "running") return { error: "ready_phase" };
        if (message.setupRev !== r.setupRev) return { error: "ready_stale" };
        if (message.ready === mine.ready) return { snapshot: true };
        if (message.ready && !mine.selection) return { error: "ready_selection_required" };
        mine.ready = message.ready;
        if (message.ready) client.recovery = false;
        if (!message.ready && a) this.abort(lobby, "unready");
        else r.stateRev++;
        return { changed: true };
      }
      case "start_request": {
        if (!isHost) return { error: "ready_not_host" };
        const { setupRev, seed, runId } = message;
        if (!count(setupRev, 1) || !Number.isInteger(seed) || seed < 1 || seed > MAX_SEED || typeof runId !== "string" || !RUN_ID_PATTERN.test(runId)) return { error: "ready_invalid" };
        if (r.phase === "running") return { error: "ready_phase" };
        if (a) return a.seed === seed && a.runId === runId && a.setupRev === setupRev ? { snapshot: true } : { error: "ready_attempt" };
        if (setupRev !== r.setupRev) return { error: "ready_stale" };
        if (this.readinessSnapshot(lobby).waitingSlots.length > 0) return { error: "ready_waiting" };
        const participants = new Map([...lobby.members.entries()].sort((x, y) => x[0] - y[0]));
        const attempt = { id: String(this.newAttemptId()), setupRev, hostSlot: lobby.hostSlot, host: client, participants, seed, runId, party: participants.size, deadlineMs: this.now() + this.countdownMs, prepareDeadlineMs: 0, prepared: new Set(), timer: null };
        attempt.timer = this.timers.set(() => this.countdownElapsed(lobby, attempt), this.countdownMs);
        r.attempt = attempt;
        r.phase = "countdown";
        r.stateRev++;
        for (const member of lobby.members.values()) member.recovery = false;
        return { changed: true };
      }
      case "start_cancel": {
        if (!isHost) return { error: "ready_not_host" };
        if (!attemptText(message.attemptId)) return { error: "ready_invalid" };
        if (!a) return { error: "ready_phase" };
        if (message.attemptId !== a.id) return { error: "ready_attempt" };
        this.abort(lobby, "cancel");
        return { changed: true };
      }
      case "launch_prepared":
      case "launch_failed": {
        const failed = message.t === "launch_failed";
        if (!attemptText(message.attemptId)) return { error: "ready_invalid" };
        if (failed ? typeof message.code !== "string" || !FAILURE_CODES.has(message.code) : !count(message.setupRev, 1)) return { error: "ready_invalid" };
        if (!a) return { error: r.phase === "running" ? "ready_phase" : "ready_attempt" };
        if (message.attemptId !== a.id || a.participants.get(client.slot) !== client) return { error: "ready_attempt" };
        if (failed) {
          this.abort(lobby, "preparation_failed");
          return { changed: true };
        }
        if (message.setupRev !== a.setupRev) return { error: "ready_stale" };
        if (r.phase !== "preparing") return { error: "ready_phase" };
        if (a.prepared.has(client.slot)) return { snapshot: true };
        a.prepared.add(client.slot);
        r.stateRev++;
        if (a.prepared.size === a.participants.size) this.commit(lobby, a);
        return { changed: true };
      }
      default:
        return { error: "ready_invalid" };
    }
  }

  // The host's status report. In a readiness lobby a fresh "run" is only
  // accepted after launch_commit, or from a connection that came back through
  // resume/takeover (an existing dig being recovered). Returns false when ignored.
  reportStatus(client, state, depth) {
    const lobby = client.lobby;
    if (!lobby || client.slot !== lobby.hostSlot) return false;
    const want = state === "run" ? "run" : "lobby";
    const r = lobby.readiness;
    if (r) {
      if (want === "run" && lobby.state !== "run") {
        if (!client.recovery || r.phase !== "idle") return false;
        r.phase = "running";
        for (const s of r.members.values()) s.ready = false;
        for (const member of lobby.members.values()) member.recovery = false;
        r.stateRev++;
      } else if (want === "lobby") {
        client.recovery = false;
        if (lobby.state === "run") {
          // Back from a finished dig: everyone readies again for the next one.
          r.phase = "idle";
          this.resetConsent(lobby);
          r.stateRev++;
        }
      }
    }
    lobby.state = want;
    lobby.depth = Math.max(1, Math.min(3, Number(depth) || 1));
    if (lobby.state === "lobby") lobby.checkpoint = null;
    return true;
  }
}

// Wraps a relay packet with its source slot. Returns null for malformed packets.
export function routePacket(client, data) {
  const lobby = client.lobby;
  if (!lobby || data.length < 2) return null;
  const target = data[0];
  if (target === CHECKPOINT_TARGET) {
    if (client.slot === lobby.hostSlot) lobby.checkpoint = Buffer.from(data.subarray(1));
    return null;
  }
  const out = Buffer.allocUnsafe(data.length);
  data.copy(out);
  out[0] = client.slot;
  const recipients = [];
  if (target === 0) {
    for (const [slot, member] of lobby.members) if (slot !== client.slot) recipients.push(member);
  } else if (target !== client.slot && lobby.members.has(target)) {
    recipients.push(lobby.members.get(target));
  }
  return { out, recipients };
}
