// Owner dashboard data (roadmap phase 6). Records a small set of operational
// events, per-account activity days and daily aggregates, and answers the
// read-only admin queries. No IP addresses, fingerprints, chat, passwords or
// tokens are stored. Client-reported platform and play time are hints, not proof.
//
// Retention: detailed events 30 days, activity days 90 days, daily aggregates
// 12 months. Profiles, runs and the operation ledger (reward deduplication) are
// never touched here. Deleting a user cascades to their events and activity.
import crypto from "node:crypto";

const DAY_MS = 24 * 60 * 60 * 1000;
export const RETENTION = { events: 30, activity: 90, aggregates: 366 };
export const PLATFORMS = ["web", "windows", "android"];
export const LOGIN_METHODS = ["sign_in", "device", "verification", "two_factor", "refresh"];
const MAX_REPORT_SECONDS = 300;
const PAGE_SIZE = 25;

const eventId = () => "evt_" + crypto.randomBytes(12).toString("base64url");
export const utcDay = (ms) => new Date(ms).toISOString().slice(0, 10);
const addDays = (day, n) => utcDay(Date.parse(day + "T00:00:00Z") + n * DAY_MS);
const platformOf = (value) => (PLATFORMS.includes(value) ? value : null);

// "ada@example.com" → "a••@example.com". Lists only ever show this form.
export function maskEmail(email) {
  const [name, domain] = String(email || "").split("@");
  if (!domain) return "•••";
  return `${name.slice(0, 1)}${"•".repeat(Math.min(Math.max(name.length - 1, 2), 6))}@${domain}`;
}

export function createAnalytics({ pool, now = () => Date.now(), log = console.log }) {
  const at = () => new Date(now());

  // Never let analytics break sign-in or progress saving.
  async function record({ kind, outcome = null, method = null, userId = null, accountId = null, platform = null, gameVersion = null, data = {} }, db = pool) {
    try {
      await db.query(
        `insert into analytics_event (id, at, kind, outcome, method, user_id, account_id, platform, game_version, data) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [eventId(), at(), kind, outcome, method, userId, accountId, platformOf(platform), Number.isInteger(gameVersion) ? gameVersion : null, data],
      );
    } catch (error) {
      log(`analytics: could not record ${kind}: ${error.message}`);
    }
  }

  // Marks the account active today; adds foreground seconds (capped per report and per day).
  async function activity(accountId, platform, seconds = 0, db = pool) {
    const add = Math.max(0, Math.min(MAX_REPORT_SECONDS, Math.floor(Number(seconds) || 0)));
    const p = platformOf(platform);
    await db.query(
      `insert into activity_day (account_id, day, seconds, platforms, last_at) values ($1, $2, $3, $4, $5)
       on conflict (account_id, day) do update set
         seconds = least(86400, activity_day.seconds + excluded.seconds),
         platforms = (select array(select distinct unnest(activity_day.platforms || excluded.platforms) order by 1)),
         last_at = greatest(activity_day.last_at, excluded.last_at)`,
      [accountId, utcDay(now()), add, p ? [p] : [], at()],
    );
    return { seconds: add };
  }

  // Every metric for one UTC day, computed from the detailed tables.
  async function computeDay(day) {
    const start = day + "T00:00:00Z";
    const end = addDays(day, 1) + "T00:00:00Z";
    const metrics = {};
    const put = (key, value) => { if (Number(value)) metrics[key] = Number(value); };
    const q = (sql, params = []) => pool.query(sql, [start, end, ...params]);
    put("registrations", (await q(`select count(*) n from "user" where "createdAt" >= $1 and "createdAt" < $2`)).rows[0].n);
    for (const r of (await q(`select method, outcome, count(*) n from analytics_event where kind = 'login' and at >= $1 and at < $2 group by 1, 2`)).rows) put(`login.${r.method}.${r.outcome}`, r.n);
    const active = (await pool.query(
      `select count(distinct account_id) filter (where day = $1::date) dau,
              count(distinct account_id) filter (where day > $1::date - 7) wau,
              count(distinct account_id) mau,
              coalesce(sum(seconds) filter (where day = $1::date), 0) seconds
       from activity_day where day > $1::date - 30 and day <= $1::date`, [day])).rows[0];
    put("dau", active.dau); put("wau", active.wau); put("mau", active.mau); put("play_seconds", active.seconds);
    for (const r of (await q(`select platform, game_version, count(*) n from analytics_event where kind = 'run_start' and at >= $1 and at < $2 group by 1, 2`)).rows) {
      put("runs.started", (metrics["runs.started"] || 0) + Number(r.n));
      put(`runs.platform.${r.platform}`, (metrics[`runs.platform.${r.platform}`] || 0) + Number(r.n));
      put(`runs.version.${r.game_version}`, (metrics[`runs.version.${r.game_version}`] || 0) + Number(r.n));
    }
    const results = (await q(
      `select count(*) n, count(*) filter (where (data->>'won')::boolean) wins, count(*) filter (where (data->>'abandoned')::boolean) abandoned, coalesce(max((data->>'depth')::int), 0) deepest
       from analytics_event where kind = 'run_result' and at >= $1 and at < $2`)).rows[0];
    put("runs.finished", results.n); put("runs.wins", results.wins); put("runs.abandoned", results.abandoned); put("runs.deepest", results.deepest);
    for (const r of (await q(`select data->>'character' c, count(*) n from analytics_event where kind = 'run_result' and at >= $1 and at < $2 group by 1`)).rows) put(`runs.character.${r.c}`, r.n);
    for (const r of (await q(`select outcome, count(*) n from analytics_event where kind = 'api_error' and at >= $1 and at < $2 group by 1`)).rows) put(`sync.error.${r.outcome}`, r.n);
    put("sync.replays", (await q(`select count(*) n from analytics_event where kind = 'replay' and at >= $1 and at < $2`)).rows[0].n);
    return metrics;
  }

  // Stores aggregates for complete days that still have detail. Idempotent.
  async function rollup() {
    const today = utcDay(now());
    const last = (await pool.query(`select max(day)::text d from daily_stat_day`)).rows[0].d;
    const first = last ? addDays(last, 1) : addDays(today, -RETENTION.events);
    for (let day = first; day < today; day = addDays(day, 1)) {
      const metrics = await computeDay(day);
      const client = await pool.connect();
      try {
        await client.query("begin");
        await client.query(`delete from daily_stat where day = $1`, [day]);
        for (const [metric, value] of Object.entries(metrics)) await client.query(`insert into daily_stat (day, metric, value) values ($1, $2, $3)`, [day, metric, value]);
        await client.query(`insert into daily_stat_day (day) values ($1) on conflict do nothing`, [day]);
        await client.query("commit");
      } catch (error) {
        await client.query("rollback").catch(() => {});
        throw error;
      } finally {
        client.release();
      }
    }
  }

  // Aggregate first so pruning never loses a day that wasn't summarized.
  async function prune() {
    await rollup();
    const today = utcDay(now());
    await pool.query(`delete from analytics_event where at < $1`, [addDays(today, -RETENTION.events) + "T00:00:00Z"]);
    await pool.query(`delete from activity_day where day < $1`, [addDays(today, -RETENTION.activity)]);
    await pool.query(`delete from daily_stat where day < $1`, [addDays(today, -RETENTION.aggregates)]);
    await pool.query(`delete from daily_stat_day where day < $1`, [addDays(today, -RETENTION.aggregates)]);
  }

  // Daily series for [from, to] (UTC dates, at most 366 days). Today is computed live.
  async function stats(from, to) {
    const today = utcDay(now());
    await rollup();
    const rows = (await pool.query(`select day::text as day, metric, value from daily_stat where day >= $1 and day <= $2`, [from, to])).rows;
    const byDay = new Map();
    for (const r of rows) {
      if (!byDay.has(r.day)) byDay.set(r.day, {});
      byDay.get(r.day)[r.metric] = Number(r.value);
    }
    const days = [];
    for (let day = from; day <= to && day <= today; day = addDays(day, 1)) days.push({ day, metrics: day === today ? await computeDay(day) : byDay.get(day) || {} });
    const window = (await pool.query(
      `select count(distinct account_id) filter (where day = $1::date) dau,
              count(distinct account_id) filter (where day > $1::date - 7) wau,
              count(distinct account_id) mau
       from activity_day where day > $1::date - 30 and day <= $1::date`, [today])).rows[0];
    return { from, to, today, generated_at: at().toISOString(), active: { dau: Number(window.dau), wau: Number(window.wau), mau: Number(window.mau) }, days };
  }

  async function users({ q = "", page = 1 }) {
    const search = String(q).trim().slice(0, 64);
    const offset = (Math.max(1, Math.min(10000, Number(page) || 1)) - 1) * PAGE_SIZE;
    const where = search ? `where g.id = $1 or g.name ilike $2 or lower(u.email) = lower($1)` : "";
    const params = search ? [search, `%${search.replace(/[\\%_]/g, "\\$&")}%`] : [];
    const total = Number((await pool.query(`select count(*) n from game_account g join "user" u on u.id = g.user_id ${where}`, params)).rows[0].n);
    const rows = (await pool.query(
      `select g.id, g.name, u.email, u."emailVerified" verified, u."createdAt" created_at, u.role,
              (select max(s."createdAt") from session s where s."userId" = u.id) last_login,
              (select max(a.last_at) from activity_day a where a.account_id = g.id) last_active,
              (select r.platform from game_run r where r.account_id = g.id order by r.started_at desc limit 1) platform
       from game_account g join "user" u on u.id = g.user_id ${where}
       order by u."createdAt" desc limit ${PAGE_SIZE} offset ${offset}`, params)).rows;
    return {
      total, page: offset / PAGE_SIZE + 1, page_size: PAGE_SIZE,
      users: rows.map((r) => ({ id: r.id, name: r.name, email: maskEmail(r.email), verified: r.verified, role: r.role === "admin" ? "admin" : "player", registered_at: r.created_at, last_login_at: r.last_login, last_active_at: r.last_active, platform: r.platform })),
    };
  }

  async function user(accountId) {
    const r = (await pool.query(
      `select g.id, g.name, g.created_at account_created, u.email, u."emailVerified" verified, u."createdAt" created_at, u.role, u."twoFactorEnabled" two_factor,
              p.revision, p.data, p.updated_at, p.adopted_at
       from game_account g join "user" u on u.id = g.user_id join profile p on p.account_id = g.id where g.id = $1`, [accountId])).rows[0];
    if (!r) return null;
    const runs = (await pool.query(
      `select platform, game_version, status, started_at, finished_at from game_run where account_id = $1 order by started_at desc limit 10`, [accountId])).rows;
    const lastLogin = (await pool.query(`select max(e.at) at from analytics_event e join game_account g on g.user_id = e.user_id where g.id = $1 and e.kind = 'login' and e.outcome = 'success' and e.method <> 'refresh'`, [accountId])).rows[0].at;
    const session = (await pool.query(`select max(s."createdAt") at, count(*) filter (where s."expiresAt" > now()) active from session s join game_account g on g.user_id = s."userId" where g.id = $1`, [accountId])).rows[0];
    const days = (await pool.query(`select day::text as day, seconds, platforms from activity_day where account_id = $1 order by day desc limit 30`, [accountId])).rows;
    const health = (await pool.query(
      `select count(*) filter (where kind = 'api_error') errors, count(*) filter (where kind = 'replay') replays,
              max(at) filter (where kind = 'api_error') last_error
       from analytics_event where account_id = $1`, [accountId])).rows[0];
    const lastOp = (await pool.query(`select max(created_at) at from operation where account_id = $1`, [accountId])).rows[0].at;
    const d = r.data || {};
    return {
      id: r.id, name: r.name, email: r.email, verified: r.verified, role: r.role === "admin" ? "admin" : "player", two_factor: Boolean(r.two_factor),
      registered_at: r.created_at, last_login_at: lastLogin || session.at, active_sessions: Number(session.active),
      last_active_at: days[0] ? days[0].day : null,
      profile: { revision: Number(r.revision), runs: d.runs ?? 0, wins: d.wins ?? 0, kills: d.kills ?? 0, zenny: d.zenny ?? 0, circuits: Object.values(d.trees || {}).reduce((n, list) => n + (Array.isArray(list) ? list.length : 0), 0), discovered: Object.keys(d.discovered || {}).length, updated_at: r.updated_at, adopted_at: r.adopted_at },
      sync: { errors_30d: Number(health.errors), replays_30d: Number(health.replays), last_error_at: health.last_error, last_operation_at: lastOp },
      runs: runs.map((x) => ({ platform: x.platform, game_version: x.game_version, status: x.status, started_at: x.started_at, finished_at: x.finished_at })),
      activity: days.map((x) => ({ day: x.day, seconds: x.seconds, platforms: x.platforms })),
    };
  }

  return { now, record, activity, computeDay, rollup, prune, stats, users, user };
}
