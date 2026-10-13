// Lobby bookkeeping and packet relay for Relic Diver co-op.
//
// Text frames carry small JSON lobby commands. Binary frames carry game
// packets that the server never inspects: a client sends [target][payload]
// (target 0 = every other member) and members receive [source][payload].
// Slot 1 is always the lobby host, who runs the authoritative simulation.

export const MAX_PLAYERS = 4;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 5;

export function cleanText(value, max) {
  if (typeof value !== "string") return "";
  // Drop control characters and collapse whitespace so names render safely in the HUD.
  return value.replace(/[\u0000-\u001f\u007f-\u009f]/g, "").replace(/\s+/g, " ").trim().slice(0, max);
}

export class LobbyRegistry {
  constructor({ maxLobbies = 200, random = Math.random } = {}) {
    this.maxLobbies = maxLobbies;
    this.random = random;
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

  create(client, { name, isPublic }) {
    if (this.lobbies.size >= this.maxLobbies) return { error: "server_full" };
    const code = this.newCode();
    const lobby = {
      code,
      name: cleanText(name, 28) || `${client.name}'s Dig`,
      isPublic: isPublic !== false,
      state: "lobby",
      depth: 1,
      created: Date.now(),
      members: new Map(),
    };
    this.lobbies.set(code, lobby);
    this.addMember(lobby, client, 1);
    return { lobby };
  }

  join(client, code) {
    const lobby = this.lobbies.get(cleanText(code, 12).toUpperCase());
    if (!lobby) return { error: "not_found" };
    if (lobby.members.size >= MAX_PLAYERS) return { error: "full" };
    let slot = 2;
    while (lobby.members.has(slot)) slot++;
    this.addMember(lobby, client, slot);
    return { lobby };
  }

  addMember(lobby, client, slot) {
    client.lobby = lobby;
    client.slot = slot;
    lobby.members.set(slot, client);
  }

  // Returns the lobby the client left and whether that lobby closed.
  leave(client) {
    const lobby = client.lobby;
    if (!lobby) return null;
    lobby.members.delete(client.slot);
    client.lobby = null;
    const slot = client.slot;
    client.slot = 0;
    const closed = slot === 1 || lobby.members.size === 0;
    if (closed) {
      this.lobbies.delete(lobby.code);
      for (const member of lobby.members.values()) {
        member.lobby = null;
        member.slot = 0;
      }
    }
    return { lobby, slot, closed };
  }

  publicList() {
    const list = [];
    for (const lobby of this.lobbies.values()) {
      if (!lobby.isPublic) continue;
      list.push(this.summary(lobby));
    }
    list.sort((a, b) => b.created - a.created);
    return list.slice(0, 50);
  }

  summary(lobby) {
    const host = lobby.members.get(1);
    return {
      code: lobby.code,
      name: lobby.name,
      host: host ? host.name : "",
      players: lobby.members.size,
      max: MAX_PLAYERS,
      state: lobby.state,
      depth: lobby.depth,
      created: lobby.created,
    };
  }

  describe(lobby) {
    const players = [];
    for (const [slot, member] of [...lobby.members.entries()].sort((a, b) => a[0] - b[0])) players.push({ slot, name: member.name });
    return { ...this.summary(lobby), isPublic: lobby.isPublic, players };
  }
}

// Wraps a relay packet with its source slot. Returns null for malformed packets.
export function routePacket(client, data) {
  const lobby = client.lobby;
  if (!lobby || data.length < 2) return null;
  const target = data[0];
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
