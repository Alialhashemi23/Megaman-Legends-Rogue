// Operator-only: grant or revoke the read-only admin role.
//   node server/admin-role.js acc_XXXX            grant (the account's email must be verified)
//   node server/admin-role.js acc_XXXX --revoke   revoke
//   node server/admin-role.js --list              show current admins
// There is deliberately no API for this. Find an account id in the player's
// /api/v1/profile response, or ask them for it.
import { createPool } from "./accounts/db.js";

const [target, flag] = process.argv.slice(2);
if (!process.env.DATABASE_URL || !target) {
  console.error("Usage: DATABASE_URL=… node server/admin-role.js <account id> [--revoke] | --list");
  process.exit(1);
}
const pool = createPool(process.env.DATABASE_URL);
try {
  if (target === "--list") {
    const r = await pool.query(`select g.id, g.name, u.email from game_account g join "user" u on u.id = g.user_id where u.role = 'admin' order by g.created_at`);
    console.log(r.rows.length ? r.rows.map((x) => `${x.id}  ${x.name}  ${x.email}`).join("\n") : "No admins.");
  } else {
    const r = await pool.query(`select u.id, u."emailVerified" as verified, u.email from game_account g join "user" u on u.id = g.user_id where g.id = $1`, [target]);
    const user = r.rows[0];
    if (!user) throw new Error(`No account ${target}.`);
    if (!user.verified && flag !== "--revoke") throw new Error(`${user.email} hasn't verified their email; admin needs a verified account.`);
    const role = flag === "--revoke" ? "player" : "admin";
    await pool.query(`update "user" set role = $2 where id = $1`, [user.id, role]);
    // Existing sessions pick up the role on their next request; revoke them so a revoke takes effect now.
    if (role === "player") await pool.query(`delete from session where "userId" = $1`, [user.id]);
    console.log(`${target} (${user.email}) is now ${role}.`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await pool.end();
}
