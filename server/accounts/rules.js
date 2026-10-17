// Server copy of the game's permanent-progress rules (scripts/progression.gd and
// finish_run()/ITEMS in scripts/game.gd). The account server applies run
// results and purchases itself, so these must match the game exactly;
// test/rules.test.js parses the GDScript and fails if they drift apart.

export const PROFILE_VERSION = 4;
export const CHARACTERS = 4;
// Workshop grid (DiverProgression.NODES/LINKS): buy a node linked to one you own.
export const START = "frame";
export const NODES = [
  { id: "frame", cost: 100 },
  { id: "mobility", cost: 140 },
  { id: "salvage", cost: 180 },
  { id: "plating", cost: 160 },
  { id: "servos", cost: 200 },
  { id: "barrel", cost: 220 },
  { id: "ability", cost: 260 },
  { id: "magnet", cost: 220 },
  { id: "mastery", cost: 400 },
  { id: "loader", cost: 340 },
  { id: "ability2", cost: 480 },
  { id: "cell", cost: 420 },
  { id: "spec_a", cost: 600 },
  { id: "spec_b", cost: 600 },
];
export const LINKS = [["frame", "mobility"], ["frame", "salvage"], ["frame", "plating"], ["plating", "servos"], ["plating", "barrel"], ["servos", "mobility"], ["barrel", "salvage"], ["mobility", "magnet"], ["salvage", "ability"], ["magnet", "mastery"], ["ability", "mastery"], ["magnet", "loader"], ["mastery", "cell"], ["ability", "ability2"], ["loader", "cell"], ["ability2", "cell"], ["loader", "spec_a"], ["ability2", "spec_b"]];
// Lifetime-kill gates for parts (ITEMS[*].unlock in game.gd).
export const PART_GATES = { lens: 0, spring: 0, heart: 0, boots: 0, shell: 0, moss: 0, ember: 40, coil: 40, prism: 100, echo: 100, split: 220, frost: 220, clover: 220, refractor: 150, flare: 150, shatter: 300, overclock: 300 };
// Gates from profile v1, kept as legacy unlocks when migrating.
export const OLD_GATES = { ember: 10, coil: 10, prism: 25, echo: 25, split: 50, frost: 50, clover: 50 };
const LIMIT = 100000000;

export function fresh() {
  return { version: PROFILE_VERSION, kills: 0, runs: 0, wins: 0, deepest: 0, discovered: {}, best_time: 0, zenny: 0, trees: {}, legacy_unlocks: [] };
}

export const node = (id) => NODES.find((entry) => entry.id === id) || null;
export const neighbors = (id) => LINKS.flatMap(([a, b]) => (a === id ? [b] : b === id ? [a] : []));
export const reachable = (owned, id) => id === START || neighbors(id).some((other) => owned.includes(other));

// A valid tree is empty, or a connected set of nodes containing the start.
export function connected(owned) {
  if (owned.length === 0) return true;
  if (!owned.includes(START)) return false;
  const seen = new Set([START]);
  const queue = [START];
  while (queue.length) for (const other of neighbors(queue.shift())) if (owned.includes(other) && !seen.has(other)) { seen.add(other); queue.push(other); }
  return seen.size === owned.length;
}
const isNumber = (value) => typeof value === "number" && Number.isFinite(value);
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

// Mirrors DiverProgression.validate(): returns a clean profile or null.
export function validateProfile(data) {
  if (!isObject(data)) return null;
  const result = fresh();
  const version = data.version ?? 1;
  if (!isNumber(version) || version < 1 || version > PROFILE_VERSION) return null;
  for (const key of ["kills", "runs", "wins", "deepest", "zenny"]) {
    const value = data[key] ?? 0;
    if (!isNumber(value) || value < 0 || value > LIMIT || value !== Math.floor(value)) return null;
    result[key] = value;
  }
  if (data.revision !== undefined && (!isNumber(data.revision) || data.revision < 0 || data.revision > LIMIT || data.revision !== Math.floor(data.revision))) return null;
  if (result.deepest > 3 || result.wins > result.runs) return null;
  const best = data.best_time ?? 0;
  if (!isNumber(best) || best < 0 || best > LIMIT) return null;
  result.best_time = best;
  const discovered = data.discovered ?? {};
  if (!isObject(discovered) || Object.keys(discovered).length > 64) return null;
  for (const [id, value] of Object.entries(discovered)) if (typeof value !== "boolean") return null; else result.discovered[id] = value;
  const trees = data.trees ?? {};
  if (!isObject(trees) || Object.keys(trees).length > CHARACTERS) return null;
  for (const [character, list] of Object.entries(trees)) {
    if (!["0", "1", "2", "3"].includes(character) || !Array.isArray(list)) return null;
    const seen = [];
    for (const id of list) {
      if (typeof id !== "string" || !node(id) || seen.includes(id)) return null;
      seen.push(id);
    }
    if (!connected(seen)) return null;
    result.trees[character] = seen;
  }
  const legacy = data.legacy_unlocks ?? [];
  if (!Array.isArray(legacy) || legacy.length > Object.keys(OLD_GATES).length) return null;
  for (const id of legacy) {
    if (typeof id !== "string" || !(id in OLD_GATES) || result.legacy_unlocks.includes(id)) return null;
    result.legacy_unlocks.push(id);
  }
  if (version === 1) for (const [id, gate] of Object.entries(OLD_GATES)) if (result.kills >= gate && !result.legacy_unlocks.includes(id)) result.legacy_unlocks.push(id);
  return result;
}

export function isEmpty(profile) {
  return profile.runs === 0 && profile.kills === 0 && profile.zenny === 0 && Object.keys(profile.trees).length === 0;
}

// DiverProgression.reward()
export function reward(depth, guardians, scrap) {
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  return clamp(depth, 1, 3) * 25 + clamp(guardians, 0, 3) * 60 + Math.floor(clamp(scrap, 0, 1000000) / 5);
}

// Shape and bounds of a reported run. Returns a clean outcome or null.
export function validateOutcome(outcome) {
  if (!isObject(outcome)) return null;
  const int = (key, lo, hi) => {
    const v = outcome[key];
    return isNumber(v) && v === Math.floor(v) && v >= lo && v <= hi ? v : null;
  };
  const clean = {
    won: outcome.won === true,
    abandoned: outcome.abandoned === true,
    depth: int("depth", 1, 3),
    guardians: int("guardians", 0, 3),
    scrap: int("scrap", 0, 100000),
    kills: int("kills", 0, 5000),
    character: int("character", 0, CHARACTERS - 1),
    run_time: isNumber(outcome.run_time) && outcome.run_time >= 0 && outcome.run_time <= 86400 ? outcome.run_time : null,
  };
  if (Object.values(clean).some((v) => v === null)) return null;
  if (typeof outcome.won !== "boolean" || clean.guardians > clean.depth) return null;
  if (clean.won && (clean.depth !== 3 || clean.guardians !== 3 || clean.abandoned)) return null;
  return clean;
}

// finish_run() for a finished dig, retire_saved_dig() for an abandoned one.
export function applyOutcome(profile, outcome) {
  const next = structuredClone(profile);
  next.version = PROFILE_VERSION;
  const before = next.kills;
  next.kills = Math.min(LIMIT, next.kills + outcome.kills);
  let zenny = 0;
  if (!outcome.abandoned) {
    zenny = reward(outcome.depth, outcome.guardians, outcome.scrap);
    next.zenny = Math.min(LIMIT, next.zenny + zenny);
    next.runs += 1;
    next.deepest = Math.max(next.deepest, outcome.depth);
    if (outcome.won) {
      next.wins += 1;
      if (next.best_time === 0 || outcome.run_time < next.best_time) next.best_time = outcome.run_time;
    }
  }
  const newUnlocks = Object.entries(PART_GATES).filter(([, gate]) => gate > before && gate <= next.kills).map(([id]) => id);
  return { profile: next, zenny, newUnlocks };
}

// DiverProgression.can_buy() plus the purchase itself. Returns {profile} or {error}.
export function buy(profile, character, id) {
  const entry = node(id);
  if (!Number.isInteger(character) || character < 0 || character >= CHARACTERS || !entry) return { error: "Unknown digger or skill." };
  const owned = profile.trees[String(character)] || [];
  if (owned.includes(id)) return { error: "Already owned." };
  if (!reachable(owned, id)) return { error: "Buy a linked skill first." };
  if (profile.zenny < entry.cost) return { error: "Not enough Zenny." };
  const next = structuredClone(profile);
  next.version = PROFILE_VERSION;
  next.zenny -= entry.cost;
  next.trees[String(character)] = [...owned, id];
  return { profile: next };
}

export function addDiscoveries(profile, parts) {
  const next = structuredClone(profile);
  for (const id of parts) next.discovered[id] = true;
  return next;
}
