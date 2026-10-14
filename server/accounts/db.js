// PostgreSQL schema for account progress. Better Auth owns its tables (user,
// session, account, verification, deviceCode); these migrations add the game's
// tables on top. Migrations run only through `node server/migrate.js` (or the
// test harness), never implicitly when the game server starts.
import pg from "pg";
import { getMigrations } from "better-auth/db/migration";

export function createPool(url, log = console.error) {
  const pool = new pg.Pool({ connectionString: url, max: 10, idleTimeoutMillis: 30000 });
  // An idle connection dropping (database restart, network blip) must not crash the game server;
  // the pool reconnects on the next query.
  pool.on("error", (error) => log(`database connection lost: ${error.message}`));
  return pool;
}

export const MIGRATIONS = [
  {
    id: "001_game_accounts",
    sql: `
      create table game_account (
        id text primary key,
        user_id text not null unique references "user"(id) on delete cascade,
        name text not null,
        created_at timestamptz not null default now()
      );
      create table profile (
        account_id text primary key references game_account(id) on delete cascade,
        revision bigint not null default 0,
        data jsonb not null,
        adopted_at timestamptz,
        updated_at timestamptz not null default now()
      );
      create table game_run (
        id text primary key,
        account_id text not null references game_account(id) on delete cascade,
        status text not null check (status in ('active', 'superseded', 'finished')),
        platform text not null,
        game_version integer not null,
        started_at timestamptz not null default now(),
        lease_expires_at timestamptz not null,
        finished_at timestamptz
      );
      create index game_run_account on game_run (account_id, status);
      create table operation (
        account_id text not null references game_account(id) on delete cascade,
        op_id text not null,
        kind text not null,
        body_hash text not null,
        status integer not null,
        response jsonb not null,
        created_at timestamptz not null default now(),
        primary key (account_id, op_id)
      );
      create table lobby_ticket (
        hash text primary key,
        account_id text not null references game_account(id) on delete cascade,
        expires_at timestamptz not null,
        used_at timestamptz
      );
      create index lobby_ticket_expiry on lobby_ticket (expires_at);
    `,
  },
];

// Auth tables first (game tables reference "user"), then ours in order.
export async function migrate(pool, authOptions, log = console.log) {
  const auth = await getMigrations(authOptions);
  if (auth.toBeCreated.length || auth.toBeAdded.length) {
    log(`auth schema: creating ${auth.toBeCreated.map((t) => t.table).join(", ") || "-"}; adding columns to ${auth.toBeAdded.map((t) => t.table).join(", ") || "-"}`);
    await auth.runMigrations();
  }
  await pool.query(`create table if not exists schema_migrations (id text primary key, applied_at timestamptz not null default now())`);
  const done = new Set((await pool.query(`select id from schema_migrations`)).rows.map((r) => r.id));
  for (const step of MIGRATIONS) {
    if (done.has(step.id)) continue;
    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query(step.sql);
      await client.query(`insert into schema_migrations (id) values ($1)`, [step.id]);
      await client.query("commit");
      log(`applied ${step.id}`);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }
}

// True when every migration has been applied, so the server can safely serve accounts.
export async function schemaReady(pool, authOptions) {
  const auth = await getMigrations(authOptions);
  if (auth.toBeCreated.length || auth.toBeAdded.length) return false;
  const exists = await pool.query(`select to_regclass('schema_migrations') as t`);
  if (!exists.rows[0].t) return false;
  const done = new Set((await pool.query(`select id from schema_migrations`)).rows.map((r) => r.id));
  return MIGRATIONS.every((step) => done.has(step.id));
}
