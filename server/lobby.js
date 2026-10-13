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

export const MAX_PLAYERS = 4;
export const CHECKPOINT_TARGET = 255;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 5;
const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{5}$/;

export function cleanText(value, max) {
  if (typeof value !== "string") return "";
  // Drop control characters and collapse whitespace so names render safely in the HUD.
  return value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").replace(/\s+/g, " ").trim().slice(0, max);
}

export function cleanCode(value) {
  return cleanText(value, 12).toUpperCase();
}

export class LobbyRegistry {
  constructor({ maxLobbies = 200, random = Math.random, runGraceMs = 15 * 60 * 1000, idleGraceMs = 3 * 60 * 1000, now = Date.now } = {}) {
    this.maxLobbies = maxLobbies;
    this.random = random;
    this.runGraceMs = runGraceMs;
    this.idleGraceMs = idleGraceMs;
    this.now = now;
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
    if (lobby.banned.has(client.playerId)) return { error: "banned" };
    const returning = lobby.knownIds.has(client.playerId);
    // A second connection with the same identity (refresh, duplicate tab) replaces the first.
    const previous = [...lobby.members.values()].find((m) => m.playerId === client.playerId);
    if (!returning) {
      if (lobby.locked) return { error: "locked" };
      if (lobby.password && cleanText(password, 24) !== lobby.password) return { error: "password" };
    }
    if (!previous && lobby.members.size >= MAX_PLAYERS) return { error: "full" };
    const replaced = previous ? this.leave(previous) : null;
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
    lobby.members.set(slot, client);
    lobby.knownIds.add(client.playerId);
    lobby.emptySince = null;
  }

  // Removes a member. Returns { lobby, slot, newHost } where newHost is set when the host role moved.
  leave(client) {
    const lobby = client.lobby;
    if (!lobby) return null;
    const slot = client.slot;
    lobby.members.delete(slot);
    client.lobby = null;
    client.slot = 0;
    let newHost = 0;
    if (lobby.members.size === 0) lobby.emptySince = this.now();
    else if (lobby.hostSlot === slot) {
      lobby.hostSlot = Math.min(...lobby.members.keys());
      newHost = lobby.hostSlot;
    }
    return { lobby, slot, newHost };
  }

  kick(host, slot) {
    const lobby = host.lobby;
    if (!lobby || host.slot !== lobby.hostSlot || slot === host.slot) return null;
    const target = lobby.members.get(slot);
    if (!target) return null;
    lobby.banned.add(target.playerId);
    lobby.knownIds.delete(target.playerId);
    this.leave(target);
    return target;
  }

  // Forget empty lobbies whose grace period ran out.
  prune() {
    const now = this.now();
    for (const [code, lobby] of this.lobbies) {
      if (lobby.emptySince === null) continue;
      const grace = lobby.state === "run" ? this.runGraceMs : this.idleGraceMs;
      if (now - lobby.emptySince >= grace) this.lobbies.delete(code);
    }
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
    const players = [];
    for (const [slot, member] of [...lobby.members.entries()].sort((a, b) => a[0] - b[0])) players.push({ slot, name: member.name, id: member.playerId });
    return { ...this.summary(lobby), isPublic: lobby.isPublic, hostSlot: lobby.hostSlot, players };
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
