// Account progress in PostgreSQL. Every write runs in one transaction that
// first locks the account's profile row, so operations for one account are
// serialized: an operation id is checked, applied and recorded exactly once.
import crypto from "node:crypto";
import { fresh, validateProfile, validateOutcome, applyOutcome, buy, addDiscoveries, isEmpty, PART_GATES } from "./rules.js";

const LEASE_MS = 10 * 60 * 1000;
const RESULT_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const TICKET_MS = 60 * 1000;
const MIGRATION_MS = 10 * 60 * 1000;

export class ApiError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const randomId = (prefix, bytes = 18) => prefix + crypto.randomBytes(bytes).toString("base64url");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
// Stable JSON so the same body always hashes the same.
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  return JSON.stringify(value);
}
const cleanName = (name) => String(name || "").replace(/[\u0000-\u001f\u007f-\u009f]/g, "").replace(/\s+/g, " ").trim().slice(0, 16) || "Digger";

export function createStore({ pool, secret, now = () => Date.now() }) {
  async function transaction(work) {
    const client = await pool.connect();
    try {
      await client.query("begin");
      const result = await work(client);
      await client.query("commit");
      return result;
    } catch (error) {
      await client.query("rollback").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  // The game account for a verified user, created on first use.
  async function ensureAccount(user) {
    const existing = await pool.query(`select id, name from game_account where user_id = $1`, [user.id]);
    if (existing.rows[0]) return existing.rows[0];
    return transaction(async (db) => {
      const id = randomId("acc_");
      const inserted = await db.query(`insert into game_account (id, user_id, name) values ($1, $2, $3) on conflict (user_id) do nothing returning id, name`, [id, user.id, cleanName(user.name)]);
      if (!inserted.rows[0]) return (await db.query(`select id, name from game_account where user_id = $1`, [user.id])).rows[0];
      await db.query(`insert into profile (account_id, revision, data) values ($1, 0, $2)`, [id, fresh()]);
      return inserted.rows[0];
    });
  }

  async function activeRun(db, accountId) {
    const r = await db.query(`select id, platform, lease_expires_at from game_run where account_id = $1 and status = 'active' and lease_expires_at > to_timestamp($2 / 1000.0) order by started_at desc limit 1`, [accountId, now()]);
    return r.rows[0] ? { id: r.rows[0].id, platform: r.rows[0].platform, lease_expires_at: r.rows[0].lease_expires_at.toISOString() } : null;
  }

  function document(account, role, row, active) {
    return { account: { id: account.id, name: account.name, role }, revision: Number(row.revision), profile: row.data, active_run: active };
  }

  async function getProfile(account, role) {
    const row = (await pool.query(`select revision, data from profile where account_id = $1`, [account.id])).rows[0];
    return document(account, role, row, await activeRun(pool, account.id));
  }

  // Runs `apply` once per operation id. Replays with the same body return the stored response.
  async function operation(account, opId, kind, body, apply) {
    if (typeof opId !== "string" || !/^[A-Za-z0-9_-]{8,64}$/.test(opId)) throw new ApiError(400, "validation", "op_id must be 8–64 letters, digits, '-' or '_'.");
    const bodyHash = sha256(kind + canonical(body));
    return transaction(async (db) => {
      const locked = (await db.query(`select revision, data from profile where account_id = $1 for update`, [account.id])).rows[0];
      const previous = (await db.query(`select body_hash, status, response from operation where account_id = $1 and op_id = $2`, [account.id, opId])).rows[0];
      if (previous) {
        if (previous.body_hash !== bodyHash) throw new ApiError(409, "operation_conflict", "That operation id was already used for something else.");
        return { status: previous.status, body: previous.response, replayed: true };
      }
      const outcome = await apply(db, locked);
      if (outcome.status < 300) await db.query(`insert into operation (account_id, op_id, kind, body_hash, status, response) values ($1, $2, $3, $4, $5, $6)`, [account.id, opId, kind, bodyHash, outcome.status, outcome.body]);
      return outcome;
    });
  }

  async function save(db, account, profile) {
    const r = await db.query(`update profile set data = $2, revision = revision + 1, updated_at = now() where account_id = $1 returning revision, data`, [account.id, profile]);
    return r.rows[0];
  }

  async function startRun(account, role, body) {
    const platform = ["web", "windows", "android"].includes(body.platform) ? body.platform : null;
    if (!platform || !Number.isInteger(body.game_version) || body.game_version < 1 || body.game_version > 1000) throw new ApiError(400, "validation", "platform must be web, windows or android, with an integer game_version.");
    return operation(account, body.op_id, "run", { platform, game_version: body.game_version, takeover: body.takeover === true }, async (db, locked) => {
      const active = await activeRun(db, account.id);
      if (active && body.takeover !== true) throw new ApiError(409, "active_run", "A dig is already running on another device.", { active_run: active });
      if (active) await db.query(`update game_run set status = 'superseded' where id = $1`, [active.id]);
      const id = randomId("run_");
      const lease = new Date(now() + LEASE_MS);
      await db.query(`insert into game_run (id, account_id, status, platform, game_version, started_at, lease_expires_at) values ($1, $2, 'active', $3, $4, to_timestamp($5 / 1000.0), $6)`, [id, account.id, platform, body.game_version, now(), lease]);
      return { status: 201, body: { run: { id, lease_expires_at: lease.toISOString() }, revision: Number(locked.revision) } };
    });
  }

  async function heartbeat(account, runId) {
    const run = (await pool.query(`select status from game_run where id = $1 and account_id = $2`, [runId, account.id])).rows[0];
    if (!run) throw new ApiError(404, "not_found", "No such dig for this account.");
    if (run.status !== "active") throw new ApiError(409, "active_run", "This dig was taken over by another device; its result will still be saved.", { active_run: await activeRun(pool, account.id) });
    const lease = new Date(now() + LEASE_MS);
    await pool.query(`update game_run set lease_expires_at = $2 where id = $1`, [runId, lease]);
    return { run: { id: runId, lease_expires_at: lease.toISOString() } };
  }

  async function finishRun(account, role, body) {
    const outcome = validateOutcome(body.outcome);
    if (typeof body.run_id !== "string" || !outcome) throw new ApiError(400, "validation", "A run_id and a valid outcome are required.");
    return operation(account, body.run_id, "result", outcome, async (db, locked) => {
      const run = (await db.query(`select status, started_at from game_run where id = $1 and account_id = $2`, [body.run_id, account.id])).rows[0];
      if (!run) throw new ApiError(404, "not_found", "No such dig for this account.");
      if (now() - run.started_at.getTime() > RESULT_WINDOW_MS) throw new ApiError(400, "validation", "This dig is too old to record.");
      const applied = applyOutcome(locked.data, outcome);
      const saved = await save(db, account, applied.profile);
      await db.query(`update game_run set status = 'finished', finished_at = now() where id = $1`, [body.run_id]);
      return { status: 200, body: { result: { zenny: applied.zenny, new_unlocks: applied.newUnlocks }, revision: Number(saved.revision), profile: saved.data } };
    });
  }

  async function purchase(account, role, body) {
    if (!Number.isInteger(body.expected_revision)) throw new ApiError(400, "validation", "expected_revision is required.");
    return operation(account, body.op_id, "purchase", { character: body.character, node: body.node, expected_revision: body.expected_revision }, async (db, locked) => {
      if (Number(locked.revision) !== body.expected_revision) throw new ApiError(409, "revision_conflict", "Your progress changed on another device. Check it and try again.", { revision: Number(locked.revision), profile: locked.data });
      const bought = buy(locked.data, body.character, body.node);
      if (bought.error) throw new ApiError(400, "validation", bought.error);
      const saved = await save(db, account, bought.profile);
      return { status: 200, body: { revision: Number(saved.revision), profile: saved.data } };
    });
  }

  async function discover(account, role, body) {
    const parts = Array.isArray(body.parts) ? body.parts : null;
    if (!parts || parts.length === 0 || parts.length > 32 || parts.some((id) => !(id in PART_GATES))) throw new ApiError(400, "validation", "parts must list 1–32 known part ids.");
    return operation(account, body.op_id, "discover", { parts: [...new Set(parts)].sort() }, async (db, locked) => {
      const next = addDiscoveries(locked.data, parts);
      if (canonical(next) === canonical(locked.data)) return { status: 200, body: { revision: Number(locked.revision), profile: locked.data } };
      const saved = await save(db, account, next);
      return { status: 200, body: { revision: Number(saved.revision), profile: saved.data } };
    });
  }

  // Confirmation tokens bind a preview to this account and this exact profile.
  function migrationToken(accountId, profile, expires) {
    const mac = crypto.createHmac("sha256", secret).update(`${accountId}|${expires}|${canonical(profile)}`).digest("base64url");
    return `mig_${expires}.${mac}`;
  }

  async function migrateGuest(account, role, body) {
    const profile = validateProfile(body.profile);
    if (!profile) throw new ApiError(400, "validation", "That isn't a valid Relic Diver profile.");
    const current = (await pool.query(`select data from profile where account_id = $1`, [account.id])).rows[0].data;
    if (body.confirm === undefined) {
      if (!isEmpty(current)) throw new ApiError(409, "not_empty", "This account already has progress, so a guest profile can't be added to it.");
      const trees = Object.values(profile.trees).reduce((n, list) => n + list.length, 0);
      return { status: 200, body: { preview: { runs: profile.runs, wins: profile.wins, zenny: profile.zenny, kills: profile.kills, trees }, confirm: migrationToken(account.id, profile, now() + MIGRATION_MS) } };
    }
    const match = typeof body.confirm === "string" && body.confirm.match(/^mig_(\d+)\.[A-Za-z0-9_-]+$/);
    const expected = match && migrationToken(account.id, profile, Number(match[1]));
    if (!match || Number(match[1]) < now() || !crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(body.confirm.padEnd(expected.length).slice(0, expected.length)))) throw new ApiError(400, "validation", "The confirmation expired or doesn't match this profile. Preview it again.");
    return operation(account, body.op_id, "migrate", { profile, confirm: body.confirm }, async (db, locked) => {
      if (!isEmpty(locked.data)) throw new ApiError(409, "not_empty", "This account already has progress, so a guest profile can't be added to it.");
      const adopted = addDiscoveries(profile, Object.keys(locked.data.discovered));
      const saved = await save(db, account, adopted);
      await db.query(`update profile set adopted_at = now() where account_id = $1`, [account.id]);
      return { status: 200, body: { revision: Number(saved.revision), profile: saved.data } };
    });
  }

  async function issueTicket(account) {
    const ticket = randomId("lt_", 24);
    await pool.query(`delete from lobby_ticket where expires_at < to_timestamp($1 / 1000.0) - interval '1 hour'`, [now()]);
    await pool.query(`insert into lobby_ticket (hash, account_id, expires_at) values ($1, $2, to_timestamp($3 / 1000.0))`, [sha256(ticket), account.id, now() + TICKET_MS]);
    return { ticket, expires_in: TICKET_MS / 1000 };
  }

  // Consumes a lobby ticket; returns the account id or null.
  async function redeemTicket(ticket) {
    if (typeof ticket !== "string" || !/^lt_[A-Za-z0-9_-]{20,64}$/.test(ticket)) return null;
    const r = await pool.query(`update lobby_ticket set used_at = now() where hash = $1 and used_at is null and expires_at > to_timestamp($2 / 1000.0) returning account_id`, [sha256(ticket), now()]);
    return r.rows[0]?.account_id || null;
  }

  return { ensureAccount, getProfile, startRun, heartbeat, finishRun, purchase, discover, migrateGuest, issueTicket, redeemTicket };
}
