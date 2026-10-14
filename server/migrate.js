// Apply account database migrations: `node server/migrate.js`.
// Needs DATABASE_URL, BETTER_AUTH_SECRET and PUBLIC_ORIGIN (the auth schema depends on its options).
// Safe to run repeatedly; it only applies what is missing. Never upgrades PostgreSQL itself.
import { createPool, migrate } from "./accounts/db.js";
import { authOptions } from "./accounts/auth.js";
import { createMailer } from "./accounts/mail.js";

const { DATABASE_URL, BETTER_AUTH_SECRET, PUBLIC_ORIGIN } = process.env;
if (!DATABASE_URL || !BETTER_AUTH_SECRET || !PUBLIC_ORIGIN) {
  console.error("Set DATABASE_URL, BETTER_AUTH_SECRET and PUBLIC_ORIGIN.");
  process.exit(1);
}
const pool = createPool(DATABASE_URL);
try {
  await migrate(pool, authOptions({ pool, secret: BETTER_AUTH_SECRET, origin: PUBLIC_ORIGIN, mailer: createMailer({}) }));
  console.log("Account database is up to date.");
} catch (error) {
  console.error(`Migration failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await pool.end();
}
