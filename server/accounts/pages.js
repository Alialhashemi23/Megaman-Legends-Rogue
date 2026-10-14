// Same-origin account pages: /account (sign in, create, verify, reset) and
// /account/device (approve a Windows/Android sign-in code). Plain HTML with a
// separate script and stylesheet so a strict Content-Security-Policy applies.

const HEADERS = {
  "Cache-Control": "no-store",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
};

function page(mode) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Relic Diver account</title><link rel="stylesheet" href="/account/app.css"><link rel="icon" href="/volnutt-icon.png"></head>
<body data-mode="${mode}"><main>
<header><p class="kicker">Mega Man Legends</p><h1>Relic Diver</h1><p class="sub" id="subtitle"></p></header>
<section id="view" aria-live="polite"><p>Loading…</p></section>
</main><script src="/account/app.js" type="module"></script></body></html>`;
}

const CSS = `
:root{--ink:#101b48;--blue:#16357f;--panel:#12336e;--select:#285fb7;--edge:#b8d7ec;--cream:#fff9df;--muted:#adc8e8;--yellow:#ffdc68;--red:#ff9565}
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:var(--blue);color:var(--cream);font:17px/1.45 system-ui,sans-serif;display:flex;justify-content:center;align-items:flex-start;padding:5vh 16px}
main{width:min(460px,100%)}header{margin-bottom:18px}.kicker{color:#7ad6ef;font-weight:700;letter-spacing:.06em;margin:0;text-transform:uppercase;font-size:14px}
h1{font-size:44px;margin:0;color:var(--yellow);letter-spacing:.02em}.sub{color:var(--muted);margin:4px 0 0}
section{background:var(--panel);border:2px solid var(--edge);border-radius:6px;padding:22px;box-shadow:0 6px 0 rgba(0,0,0,.25)}
h2{margin:0 0 14px;font-size:22px}label{display:block;margin:12px 0 4px;color:var(--muted);font-size:14px;font-weight:600}
input{width:100%;padding:11px 12px;border-radius:4px;border:2px solid var(--edge);background:var(--ink);color:var(--cream);font-size:17px}
input:focus{outline:3px solid var(--yellow);outline-offset:1px}
button{margin-top:16px;width:100%;padding:12px;border:2px solid var(--edge);border-radius:4px;background:var(--select);color:var(--cream);font-size:17px;font-weight:700;cursor:pointer}
button.secondary{background:transparent}button:focus{outline:3px solid var(--yellow);outline-offset:2px}button:disabled{opacity:.6;cursor:wait}
.row{display:flex;gap:10px}.row button{flex:1}.links{display:flex;flex-wrap:wrap;gap:14px;margin-top:16px}.links a{color:#7ad6ef}
.note{margin:14px 0 0;padding:10px 12px;border-radius:4px;background:var(--ink);border-left:4px solid var(--yellow)}.note.bad{border-color:var(--red)}
.code{font:700 34px/1 ui-monospace,monospace;letter-spacing:.12em;color:var(--yellow);text-align:center;margin:8px 0}
`;

const JS = `
const mode = document.body.dataset.mode;
const params = new URLSearchParams(location.search);
const view = document.getElementById("view");
const subtitle = document.getElementById("subtitle");
// Only same-site relative paths, so the return link can't send players elsewhere.
const back = (() => { const r = params.get("return") || "/"; return /^\\/(?!\\/)[\\w\\-./?=&%]*$/.test(r) ? r : "/"; })();
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);

async function api(path, body, method = body ? "POST" : "GET") {
  const r = await fetch("/api/auth" + path, { method, credentials: "same-origin", headers: body ? { "Content-Type": "application/json" } : {}, body: body ? JSON.stringify(body) : undefined });
  let data = null; try { data = await r.json(); } catch {}
  return { ok: r.ok, status: r.status, data };
}
const message = (data, fallback) => (data && (data.message || data.error_description || data.code || data.error)) || fallback;
function note(text, bad = false) { const p = document.createElement("p"); p.className = "note" + (bad ? " bad" : ""); p.textContent = text; view.querySelector(".note")?.remove(); view.append(p); }
function busy(form, on) { form.querySelectorAll("button").forEach((b) => (b.disabled = on)); }

function render(html, focus = "input, button") { view.innerHTML = html; view.querySelector(focus)?.focus(); }

function signInView(after) {
  subtitle.textContent = mode === "device" ? "Sign in to approve your game" : "Sign in to keep your progress on every device";
  render(\`<h2>Sign in</h2><form id="f"><label for="e">Email</label><input id="e" type="email" autocomplete="email" required>
  <label for="p">Password</label><input id="p" type="password" autocomplete="current-password" required minlength="10"><button>Sign in</button></form>
  <div class="links"><a href="#" id="create">Create an account</a><a href="#" id="forgot">Forgot password?</a></div>\`);
  document.getElementById("create").onclick = (e) => { e.preventDefault(); signUpView(after); };
  document.getElementById("forgot").onclick = (e) => { e.preventDefault(); forgotView(after); };
  const f = document.getElementById("f");
  f.onsubmit = async (e) => {
    e.preventDefault(); busy(f, true);
    const r = await api("/sign-in/email", { email: f.e.value, password: f.p.value, callbackURL: location.pathname + location.search });
    busy(f, false);
    if (r.ok) return after();
    if (r.data?.code === "EMAIL_NOT_VERIFIED") return note("Confirm your email first. We've sent the link again; check your inbox.", true);
    note(message(r.data, "Sign-in failed."), true);
  };
}

function signUpView(after) {
  subtitle.textContent = "Create an account to save your digs";
  render(\`<h2>Create an account</h2><form id="f"><label for="n">Digger name</label><input id="n" maxlength="16" required autocomplete="nickname">
  <label for="e">Email</label><input id="e" type="email" autocomplete="email" required>
  <label for="p">Password (10+ characters)</label><input id="p" type="password" autocomplete="new-password" required minlength="10" maxlength="128">
  <button>Create account</button></form><div class="links"><a href="#" id="have">I already have an account</a></div>\`);
  document.getElementById("have").onclick = (e) => { e.preventDefault(); signInView(after); };
  const f = document.getElementById("f");
  f.onsubmit = async (e) => {
    e.preventDefault(); busy(f, true);
    const r = await api("/sign-up/email", { name: f.n.value, email: f.e.value, password: f.p.value, callbackURL: location.pathname + location.search });
    busy(f, false);
    if (!r.ok) return note(message(r.data, "Couldn't create the account."), true);
    render(\`<h2>Check your email</h2><p>We sent a confirmation link to <b>\${esc(f.e.value)}</b>. Open it to finish creating your account, then come back here.</p><button class="secondary" id="again">I've confirmed it</button>\`);
    document.getElementById("again").onclick = () => signInView(after);
  };
}

function forgotView(after) {
  subtitle.textContent = "Reset your password";
  render(\`<h2>Forgot your password?</h2><form id="f"><label for="e">Email</label><input id="e" type="email" autocomplete="email" required><button>Send reset link</button></form>
  <div class="links"><a href="#" id="back">Back to sign in</a></div>\`);
  document.getElementById("back").onclick = (e) => { e.preventDefault(); signInView(after); };
  const f = document.getElementById("f");
  f.onsubmit = async (e) => {
    e.preventDefault(); busy(f, true);
    const r = await api("/request-password-reset", { email: f.e.value, redirectTo: "/account?reset=1" });
    busy(f, false);
    note(r.ok ? "If that email has an account, a reset link is on its way. It works for an hour." : message(r.data, "Couldn't send the link."), !r.ok);
  };
}

function resetView(token) {
  subtitle.textContent = "Choose a new password";
  render(\`<h2>New password</h2><form id="f"><label for="p">New password (10+ characters)</label><input id="p" type="password" autocomplete="new-password" required minlength="10" maxlength="128"><button>Save password</button></form>\`);
  const f = document.getElementById("f");
  f.onsubmit = async (e) => {
    e.preventDefault(); busy(f, true);
    const r = await api("/reset-password", { newPassword: f.p.value, token });
    busy(f, false);
    if (!r.ok) return note(message(r.data, "That link has expired. Ask for a new one."), true);
    history.replaceState(null, "", "/account");
    signInView(home); note("Password changed. Other devices were signed out; sign in again.");
  };
}

async function home() {
  const s = await api("/get-session");
  if (!s.ok || !s.data?.user) return signInView(home);
  subtitle.textContent = "Your account";
  render(\`<h2>Signed in</h2><p>Digger <b>\${esc(s.data.user.name)}</b><br><span style="color:var(--muted)">\${esc(s.data.user.email)}</span></p>
  <div class="row"><button id="play">Back to the game</button><button class="secondary" id="out">Sign out</button></div>\`);
  document.getElementById("play").onclick = () => location.assign(back);
  document.getElementById("out").onclick = async () => { await api("/sign-out", {}); signInView(home); note("Signed out."); };
}

async function device() {
  const s = await api("/get-session");
  if (!s.ok || !s.data?.user) return signInView(device);
  subtitle.textContent = "Approve a game sign-in";
  const preset = (params.get("code") || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  render(\`<h2>Enter the code from your game</h2><form id="f"><label for="c">Code</label><input id="c" required maxlength="12" autocomplete="one-time-code" value="\${esc(preset)}" style="text-transform:uppercase;letter-spacing:.12em"><button>Continue</button></form>
  <p style="color:var(--muted);margin-bottom:0">Signed in as \${esc(s.data.user.email)}</p>\`);
  const f = document.getElementById("f");
  f.onsubmit = async (e) => {
    e.preventDefault();
    const code = f.c.value.toUpperCase().replace(/[^A-Z0-9]/g, "");
    busy(f, true);
    const r = await api("/device?user_code=" + encodeURIComponent(code));
    busy(f, false);
    if (!r.ok) return note("That code isn't valid or has expired. Check the game for a new one.", true);
    const app = { "relic-windows": "Relic Diver for Windows", "relic-android": "Relic Diver for Android" }[r.data?.client_id] || "a Relic Diver game";
    render(\`<h2>Sign in \${esc(app)}?</h2><p class="code">\${esc(code.slice(0, 4))}-\${esc(code.slice(4))}</p><p>Only approve if this code is on your own screen right now. The game will be able to save progress to <b>\${esc(s.data.user.email)}</b>.</p>
    <div class="row"><button id="yes">Approve</button><button class="secondary" id="no">Deny</button></div>\`, "#yes");
    const decide = async (approve) => {
      const done = await api(approve ? "/device/approve" : "/device/deny", { userCode: code });
      render(done.ok ? \`<h2>\${approve ? "Approved" : "Denied"}</h2><p>\${approve ? "Return to your game; it will sign in by itself in a few seconds." : "The game was not signed in."} You can close this page.</p>\` : \`<h2>Something went wrong</h2><p>\${esc(message(done.data, "Try again with a new code."))}</p>\`);
    };
    document.getElementById("yes").onclick = () => decide(true);
    document.getElementById("no").onclick = () => decide(false);
  };
}

if (mode === "device") device();
else if (params.get("reset") && params.get("token")) resetView(params.get("token"));
else if (params.get("error")) { home(); setTimeout(() => note("That link has expired or was already used.", true), 50); }
else home();
`;

export function accountPage(res) {
  res.writeHead(200, { ...HEADERS, "Content-Type": "text/html; charset=utf-8" });
  res.end(page("account"));
}
export function devicePage(res) {
  res.writeHead(200, { ...HEADERS, "Content-Type": "text/html; charset=utf-8" });
  res.end(page("device"));
}
export function pageAsset(res, name) {
  const body = name === "app.js" ? JS : CSS;
  res.writeHead(200, { ...HEADERS, "Content-Type": name === "app.js" ? "text/javascript; charset=utf-8" : "text/css; charset=utf-8", "Cache-Control": "no-cache" });
  res.end(body);
}
