// Outgoing account email. A replaceable adapter: SMTP in production (MAIL_URL),
// an in-memory sink in tests. Links carry one-time tokens, so they are never logged.
import nodemailer from "nodemailer";

export function createMailer({ url, from, sink } = {}) {
  if (sink) {
    return { available: true, async send(message) { sink.push(message); } };
  }
  if (!url) return { available: false, async send() { throw new Error("mail is not configured"); } };
  const transport = nodemailer.createTransport(url);
  return {
    available: true,
    async send({ to, subject, text, html }) {
      await transport.sendMail({ from: from || "Relic Diver <noreply@localhost>", to, subject, text, html });
    },
  };
}

const escape = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export function verificationMail(to, url) {
  return {
    kind: "verify", to, url,
    subject: "Confirm your Relic Diver account",
    text: `Confirm your email to save your digs to your account:\n\n${url}\n\nIf you didn't sign up, ignore this email.`,
    html: `<p>Confirm your email to save your digs to your account.</p><p><a href="${escape(url)}">Confirm my email</a></p><p>If you didn't sign up, ignore this email.</p>`,
  };
}

export function resetMail(to, url) {
  return {
    kind: "reset", to, url,
    subject: "Reset your Relic Diver password",
    text: `Someone asked to reset your Relic Diver password. Use this link within an hour:\n\n${url}\n\nIf it wasn't you, ignore this email; your password is unchanged.`,
    html: `<p>Someone asked to reset your Relic Diver password. Use this link within an hour:</p><p><a href="${escape(url)}">Choose a new password</a></p><p>If it wasn't you, ignore this email; your password is unchanged.</p>`,
  };
}
