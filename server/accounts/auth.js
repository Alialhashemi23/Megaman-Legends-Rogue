// Better Auth configuration: email/password with verification and recovery,
// first-party device codes for Windows/Android, and bearer sessions for them.
// The admin role is a plain user field that no API can set (see admin-role.js);
// Better Auth's admin plugin is deliberately not used because it would expose
// ban, impersonation and role-editing endpoints the owner chose not to have.
import { betterAuth } from "better-auth";
import { bearer, deviceAuthorization } from "better-auth/plugins";
import { verificationMail, resetMail } from "./mail.js";

export const DEVICE_CLIENTS = ["relic-windows", "relic-android"];
const DAY = 60 * 60 * 24;

export function authOptions({ pool, secret, origin, mailer, rateLimit = true }) {
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
    plugins: [
      bearer(),
      deviceAuthorization({ expiresIn: "10m", interval: "5s", verificationUri: "/account/device", validateClient: (id) => DEVICE_CLIENTS.includes(id) }),
    ],
  };
}

export function createAuth(options) {
  return betterAuth(authOptions(options));
}
