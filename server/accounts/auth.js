// Better Auth configuration: email/password with verification and recovery,
// first-party device codes for Windows/Android, and bearer sessions for them.
// The admin role is a plain user field that no API can set (see admin-role.js);
// Better Auth's admin plugin is deliberately not used because it would expose
// ban, impersonation and role-editing endpoints the owner chose not to have.
import { betterAuth } from "better-auth";
import { bearer, deviceAuthorization, twoFactor } from "better-auth/plugins";
import { createAuthMiddleware } from "better-auth/api";
import { verificationMail, resetMail } from "./mail.js";

export const DEVICE_CLIENTS = ["relic-windows", "relic-android"];
const DAY = 60 * 60 * 24;

// Login events for the owner dashboard (phase 6), split by method. A session
// refresh is recorded separately and is never counted as a login. Successful
// authenticator checks also mark that session as allowed to open /admin.
const LOGIN_PATHS = { "/sign-in/email": "sign_in", "/device/token": "device", "/verify-email": "verification", "/two-factor/verify-totp": "two_factor", "/two-factor/verify-backup-code": "two_factor" };
const NOT_FAILURES = ["authorization_pending", "slow_down"];

function analyticsPlugin(analytics, pool) {
  const userForToken = async (token) => (token ? (await pool.query(`select "userId" from session where token = $1`, [token])).rows[0]?.userId || null : null);
  return {
    id: "relic-analytics",
    hooks: { after: [{
      matcher: (ctx) => Object.hasOwn(LOGIN_PATHS, ctx.path),
      handler: createAuthMiddleware(async (ctx) => {
        const method = LOGIN_PATHS[ctx.path];
        const returned = ctx.context.returned;
        const error = returned instanceof Error ? returned : null;
        const session = ctx.context.newSession;
        if (error && error.statusCode >= 400) {
          const code = String(error.body?.code || error.body?.error || error.statusCode).toLowerCase().slice(0, 48);
          if (!NOT_FAILURES.includes(code)) await analytics.record({ kind: "login", method, outcome: "failure", data: { code } });
          return;
        }
        if (method === "sign_in" && !session) {
          if (returned?.twoFactorRedirect) await analytics.record({ kind: "login", method, outcome: "challenge" });
          return;
        }
        if (method === "verification" && !session) return analytics.record({ kind: "login", method, outcome: "failure", data: { code: "invalid_token" } });
        const token = session?.session.token || returned?.token || returned?.access_token;
        const userId = session?.user.id || (await userForToken(token));
        if (!userId) return;
        if (method === "two_factor") await pool.query(`insert into admin_mfa_session (session_id, verified_at) select id, $2 from session where token = $1 on conflict (session_id) do update set verified_at = excluded.verified_at`, [token, new Date(analytics.now())]);
        await analytics.record({ kind: "login", method, outcome: "success", userId });
      }),
    }] },
  };
}

export function authOptions({ pool, secret, origin, mailer, rateLimit = true, analytics = null }) {
  return {
    appName: "Relic Diver",
    baseURL: origin,
    basePath: "/api/auth",
    secret,
    database: pool,
    trustedOrigins: [origin],
    emailAndPassword: {
      enabled: true,
      requireEmailVerification: true,
      minPasswordLength: 10,
      maxPasswordLength: 128,
      revokeSessionsOnPasswordReset: true,
      resetPasswordTokenExpiresIn: 60 * 60,
      sendResetPassword: async ({ user, url }) => mailer.send(resetMail(user.email, url)),
    },
    emailVerification: {
      sendOnSignUp: true,
      sendOnSignIn: true,
      autoSignInAfterVerification: true,
      expiresIn: DAY,
      sendVerificationEmail: async ({ user, url }) => mailer.send(verificationMail(user.email, url)),
    },
    user: {
      additionalFields: { role: { type: "string", required: false, defaultValue: "player", input: false } },
      deleteUser: { enabled: true },
    },
    session: { expiresIn: 7 * DAY, updateAge: DAY },
    rateLimit: {
      enabled: rateLimit,
      window: 60,
      max: 100,
      customRules: { "/sign-in/email": { window: 60, max: 10 }, "/sign-up/email": { window: 300, max: 5 }, "/request-password-reset": { window: 300, max: 3 }, "/device/code": { window: 60, max: 10 } },
    },
    advanced: {
      useSecureCookies: origin.startsWith("https://"),
      ipAddress: { ipAddressHeaders: ["cf-connecting-ip", "x-forwarded-for"] },
    },
    databaseHooks: analytics ? { session: { update: { after: async (session) => {
      if (session?.userId && session.expiresAt) await analytics.record({ kind: "login", method: "refresh", outcome: "success", userId: session.userId });
    } } } } : undefined,
    plugins: [
      bearer(),
      deviceAuthorization({ expiresIn: "10m", interval: "5s", verificationUri: "/account/device", validateClient: (id) => DEVICE_CLIENTS.includes(id) }),
      // Authenticator-app codes; required before the admin role can open /admin.
      twoFactor({ issuer: "Relic Diver" }),
      ...(analytics ? [analyticsPlugin(analytics, pool)] : []),
    ],
  };
}

export function createAuth(options) {
  return betterAuth(authOptions(options));
}
