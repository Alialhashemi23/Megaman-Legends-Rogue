// Read-only owner dashboard at /admin (roadmap phase 6). The page itself is
// static; every number comes from /api/admin/*, which checks the admin role,
// the authenticator and the session (see api.js). Same strict CSP as /account,
// so there are no inline scripts or styles; charts are SVG built in the script.

const HEADERS = {
  "Cache-Control": "no-store",
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "X-Robots-Tag": "noindex, nofollow",
  "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
};

const PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><title>Relic Diver owner dashboard</title><link rel="stylesheet" href="/admin/app.css"><link rel="icon" href="/volnutt-icon.png"></head>
<body><main>
<header><p class="kicker">Mega Man Legends</p><h1>Relic Diver</h1><p class="sub" id="subtitle">Owner dashboard · read-only · all times UTC</p></header>
<div id="view" aria-live="polite"><section><p>Loading…</p></section></div>
</main><script src="/admin/app.js" type="module"></script></body></html>`;

const CSS = `
:root{--ink:#101b48;--blue:#16357f;--panel:#12336e;--select:#285fb7;--edge:#b8d7ec;--cream:#fff9df;--muted:#adc8e8;--yellow:#ffdc68;--red:#ff9565;--cyan:#7ad6ef}
*{box-sizing:border-box}body{margin:0;min-height:100vh;background:var(--blue);color:var(--cream);font:16px/1.45 system-ui,sans-serif;padding:4vh 16px}
main{max-width:1120px;margin:0 auto}header{margin-bottom:16px}.kicker{color:var(--cyan);font-weight:700;letter-spacing:.06em;margin:0;text-transform:uppercase;font-size:14px}
h1{font-size:40px;margin:0;color:var(--yellow)}.sub{color:var(--muted);margin:4px 0 0}
section{background:var(--panel);border:2px solid var(--edge);border-radius:6px;padding:18px 20px;box-shadow:0 6px 0 rgba(0,0,0,.25);margin-bottom:18px}
h2{margin:0 0 12px;font-size:21px}h3{margin:0 0 6px;font-size:16px;color:var(--muted);font-weight:600}
label{display:block;margin:0 0 4px;color:var(--muted);font-size:13px;font-weight:600}
input{padding:9px 10px;border-radius:4px;border:2px solid var(--edge);background:var(--ink);color:var(--cream);font-size:16px;width:100%}
input:focus,button:focus,a:focus,tr.pick:focus{outline:3px solid var(--yellow);outline-offset:1px}
button{padding:9px 14px;border:2px solid var(--edge);border-radius:4px;background:var(--select);color:var(--cream);font-size:15px;font-weight:700;cursor:pointer}
button.secondary{background:transparent}button:disabled{opacity:.6;cursor:wait}button[aria-pressed=true]{background:var(--yellow);color:var(--ink)}
a{color:var(--cyan)}.muted{color:var(--muted)}.bad{color:var(--red)}
.filters{display:flex;flex-wrap:wrap;gap:10px;align-items:flex-end}.filters>div{min-width:150px}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
.tile{background:var(--ink);border-radius:4px;padding:10px 12px}.tile b{display:block;font-size:30px;color:var(--cream);line-height:1.1}.tile span{color:var(--muted);font-size:13px}
.charts{display:grid;grid-template-columns:repeat(auto-fill,minmax(500px,1fr));gap:14px}@media (max-width:560px){.charts{grid-template-columns:1fr}}
.chart{background:var(--ink);border-radius:4px;padding:12px}.chart .total{font-size:24px;font-weight:700}
svg{display:block;width:100%;height:auto}svg text{fill:var(--muted);font-size:11px}svg .bar:hover{fill:var(--cream)}
details{margin-top:6px}summary{cursor:pointer;color:var(--cyan);font-size:14px}
table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #2a4c8c}th{color:var(--muted);font-weight:600}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}tr.pick{cursor:pointer}tr.pick:hover{background:#1c428a}
.grid2{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:14px}
.note{margin:12px 0 0;padding:10px 12px;border-radius:4px;background:var(--ink);border-left:4px solid var(--yellow)}.note.bad{border-color:var(--red);color:var(--cream)}
.code{width:12ch;font:700 24px/1 ui-monospace,monospace;letter-spacing:.15em}.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
dl{display:grid;grid-template-columns:max-content 1fr;gap:4px 14px;margin:0}dt{color:var(--muted)}dd{margin:0}
`;

const JS = `
const view = document.getElementById("view");
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"})[c]);
const num = (n) => Number(n || 0).toLocaleString("en-US");
const when = (t) => t ? new Date(t).toISOString().replace("T", " ").slice(0, 16) + " UTC" : "—";
const DIGGERS = ["Mega", "Roll", "Tron", "Servbot"];
const METHODS = { sign_in: "Sign-in (password)", device: "Game device approval", verification: "Email verification", two_factor: "Authenticator check", refresh: "Session refresh (not a login)" };
const SVGNS = "http://www.w3.org/2000/svg";

async function get(path) {
  const r = await fetch(path, { credentials: "same-origin", headers: { Accept: "application/json" } });
  let data = null; try { data = await r.json(); } catch {}
  return { ok: r.ok, status: r.status, data };
}
async function post(path, body) {
  const r = await fetch(path, { method: "POST", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  let data = null; try { data = await r.json(); } catch {}
  return { ok: r.ok, status: r.status, data };
}

function gate(r) {
  const code = r.data?.error?.code;
  if (r.status === 401) view.innerHTML = '<section><h2>Sign in first</h2><p>The owner dashboard needs your browser account sign-in.</p><p><a href="/account?return=%2Fadmin">Sign in on the account page</a></p></section>';
  else if (code === "mfa_setup_required") view.innerHTML = '<section><h2>Set up your authenticator</h2><p>The dashboard needs an authenticator app on the owner account. Set it up on the <a href="/account?return=%2Fadmin">account page</a>, then come back.</p></section>';
  else if (code === "mfa_required") return codeForm();
  else if (code === "forbidden") view.innerHTML = '<section><h2>Not available</h2><p>This page is for the game\\'s owner.</p><p><a href="/">Back to the game</a></p></section>';
  else view.innerHTML = '<section><h2>Dashboard unavailable</h2><p class="bad">' + esc(r.data?.error?.message || "The server didn't answer. Try again shortly.") + '</p><button id="again">Retry</button></section>', document.getElementById("again").onclick = start;
}

function codeForm() {
  view.innerHTML = '<section><h2>Authenticator check</h2><p>Enter the 6-digit code from your authenticator app. The check lasts 12 hours on this browser session.</p><form id="f" class="row"><div><label for="c">Code</label><input id="c" class="code" inputmode="numeric" autocomplete="one-time-code" required maxlength="11"></div><button>Verify</button></form><p class="muted"><a href="#" id="backup">Use a backup code instead</a></p></section>';
  const f = document.getElementById("f");
  let backup = false;
  document.getElementById("backup").onclick = (e) => { e.preventDefault(); backup = true; f.c.removeAttribute("inputmode"); document.querySelector("label[for=c]").textContent = "Backup code"; f.c.focus(); };
  f.c.focus();
  f.onsubmit = async (e) => {
    e.preventDefault();
    f.querySelector("button").disabled = true;
    const code = backup ? f.c.value.trim() : f.c.value.replace(/\\D/g, "");
    const r = await post(backup ? "/api/auth/two-factor/verify-backup-code" : "/api/auth/two-factor/verify-totp", { code });
    f.querySelector("button").disabled = false;
    if (r.ok) return start();
    document.querySelector(".note")?.remove();
    f.insertAdjacentHTML("afterend", '<p class="note bad">That code didn\\'t work. Wait for a fresh code and try again.</p>');
  };
}

// One series per chart, so no legend: the heading names it. Each bar has a hover title and the table view below.
function barChart(days, key, { label, scale = 1, unit = "" }) {
  const values = days.map((d) => (d.metrics[key] || 0) / scale);
  const max = Math.max(1, ...values);
  const w = 520, h = 170, left = 40, bottom = 22, top = 8;
  const plotW = w - left - 6, plotH = h - top - bottom;
  const svg = document.createElementNS(SVGNS, "svg");
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", label + ", one bar per UTC day");
  const add = (tag, attrs, text) => { const el = document.createElementNS(SVGNS, tag); for (const k in attrs) el.setAttribute(k, attrs[k]); if (text !== undefined) el.textContent = text; svg.append(el); return el; };
  for (const f of [0, 0.5, 1]) {
    const y = top + plotH * (1 - f);
    add("line", { x1: left, x2: w - 6, y1: y, y2: y, stroke: "#2a4c8c", "stroke-width": 1 });
    add("text", { x: left - 6, y: y + 4, "text-anchor": "end" }, formatValue(max * f, scale));
  }
  const slot = plotW / Math.max(1, values.length);
  const bw = Math.max(1, slot - 2);
  values.forEach((v, i) => {
    const bh = v > 0 ? Math.max(2, (v / max) * plotH) : 0;
    const x = left + i * slot + (slot - bw) / 2;
    const g = document.createElementNS(SVGNS, "g");
    const hit = document.createElementNS(SVGNS, "rect");
    for (const [k, val] of Object.entries({ x: left + i * slot, y: top, width: slot, height: plotH, fill: "transparent" })) hit.setAttribute(k, val);
    const bar = document.createElementNS(SVGNS, "rect");
    for (const [k, val] of Object.entries({ class: "bar", x, y: top + plotH - bh, width: bw, height: bh, rx: Math.min(4, bw / 2), fill: "#ffdc68" })) bar.setAttribute(k, val);
    const title = document.createElementNS(SVGNS, "title");
    title.textContent = days[i].day + ": " + formatValue(v, scale) + unit;
    g.append(hit, bar, title);
    svg.append(g);
  });
  const step = Math.ceil(values.length / 6);
  days.forEach((d, i) => { if (i % step === 0 || i === days.length - 1) add("text", { x: left + i * slot + slot / 2, y: h - 6, "text-anchor": "middle" }, d.day.slice(5)); });
  return svg;
}
const formatValue = (v, scale) => scale === 1 ? num(Math.round(v)) : (Math.round(v * 10) / 10).toLocaleString("en-US");

function chartCard(days, key, opts) {
  const card = document.createElement("div");
  card.className = "chart";
  const values = days.map((d) => d.metrics[key] || 0);
  const total = opts.total === "max" ? Math.max(0, ...values) : values.reduce((a, b) => a + b, 0);
  card.innerHTML = '<h3>' + esc(opts.label) + '</h3><div class="total">' + formatValue(total / (opts.scale || 1), opts.scale || 1) + esc(opts.unit || "") + ' <span class="muted">' + esc(opts.totalLabel || "in range") + '</span></div>';
  card.append(barChart(days, key, opts));
  const rows = days.map((d) => '<tr><td>' + d.day + '</td><td class="n">' + formatValue((d.metrics[key] || 0) / (opts.scale || 1), opts.scale || 1) + '</td></tr>').join("");
  card.insertAdjacentHTML("beforeend", '<details><summary>Table view</summary><table><thead><tr><th>UTC day</th><th class="n">' + esc(opts.label) + '</th></tr></thead><tbody>' + rows + '</tbody></table></details>');
  if (opts.note) card.insertAdjacentHTML("beforeend", '<p class="muted">' + esc(opts.note) + '</p>');
  return card;
}

function sums(days, prefix) {
  const out = {};
  for (const d of days) for (const [k, v] of Object.entries(d.metrics)) if (k.startsWith(prefix)) out[k.slice(prefix.length)] = (out[k.slice(prefix.length)] || 0) + v;
  return out;
}
function table(title, head, rows, empty) {
  if (!rows.length) return '<div><h3>' + esc(title) + '</h3><p class="muted">' + esc(empty || "Nothing recorded in this range.") + '</p></div>';
  return '<div><h3>' + esc(title) + '</h3><table><thead><tr>' + head.map((h, i) => '<th' + (i ? ' class="n"' : '') + '>' + esc(h) + '</th>').join("") + '</tr></thead><tbody>' + rows.map((r) => '<tr>' + r.map((c, i) => '<td' + (i ? ' class="n"' : '') + '>' + esc(c) + '</td>').join("") + '</tr>').join("") + '</tbody></table></div>';
}

const state = { from: null, to: null, preset: 30, q: "", page: 1 };
const isoDay = (ms) => new Date(ms).toISOString().slice(0, 10);

function layout() {
  view.innerHTML = '<section><div class="filters"><div><label for="from">From (UTC)</label><input type="date" id="from"></div><div><label for="to">To (UTC)</label><input type="date" id="to"></div>' +
    '<div class="row" role="group" aria-label="Quick ranges"><button class="secondary" data-days="7">7 days</button><button class="secondary" data-days="30">30 days</button><button class="secondary" data-days="90">90 days</button><button class="secondary" data-days="365">12 months</button></div>' +
    '<button id="apply">Show</button><span class="muted" id="stamp"></span></div></section><div id="stats"><section><p>Loading statistics…</p></section></div>' +
    '<section id="users"><h2>Players</h2><form id="search" class="row"><div><label for="q">Search name, account id or exact email</label><input id="q" maxlength="64"></div><button>Search</button></form><div id="list"></div><div id="detail"></div></section>';
  document.querySelectorAll("[data-days]").forEach((b) => b.onclick = () => { state.preset = Number(b.dataset.days); state.to = null; state.from = null; loadStats(); });
  document.getElementById("apply").onclick = () => { state.from = document.getElementById("from").value || null; state.to = document.getElementById("to").value || null; state.preset = null; loadStats(); };
  document.getElementById("search").onsubmit = (e) => { e.preventDefault(); state.q = document.getElementById("q").value.trim(); state.page = 1; loadUsers(); };
}

async function loadStats() {
  const to = state.to || isoDay(Date.now());
  const from = state.from || isoDay(Date.parse(to + "T00:00:00Z") - ((state.preset || 30) - 1) * 86400000);
  document.querySelectorAll("[data-days]").forEach((b) => b.setAttribute("aria-pressed", String(Number(b.dataset.days) === state.preset)));
  const box = document.getElementById("stats");
  box.innerHTML = '<section><p>Loading statistics…</p></section>';
  const r = await get("/api/admin/stats?from=" + from + "&to=" + to);
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) return gate(r);
    box.innerHTML = '<section><p class="bad">' + esc(r.data?.error?.message || "Statistics are unavailable right now.") + '</p></section>';
    return;
  }
  const s = r.data;
  document.getElementById("from").value = s.from;
  document.getElementById("to").value = s.to;
  document.getElementById("stamp").textContent = "Updated " + when(s.generated_at);
  const live = s.live;
  const tiles = [
    [live ? num(live.connections) : "—", "connections now"], [live ? num(live.accounts) : "—", "signed-in players now"], [live ? num(live.guest_connections) : "—", "guest connections now"], [live ? num(live.lobbies) : "—", "lobbies in play"],
    [num(s.active.dau), "active today (DAU)"], [num(s.active.wau), "active 7 days (WAU)"], [num(s.active.mau), "active 30 days (MAU)"],
  ];
  box.innerHTML = '<section><h2>Right now</h2><div class="tiles">' + tiles.map(([v, l]) => '<div class="tile"><b>' + v + '</b><span>' + l + '</span></div>').join("") + '</div>' +
    '<p class="muted">Active means an account played in the foreground (dig started or play time reported) on that UTC day. Guests aren\\'t counted.</p></section>' +
    '<section><h2>Daily</h2><div class="charts" id="charts"></div></section><section><h2>Breakdown for this range</h2><div class="grid2" id="tables"></div></section>';
  const days = s.days;
  if (!days.length || days.every((d) => !Object.keys(d.metrics).length)) document.getElementById("charts").insertAdjacentHTML("beforebegin", '<p class="note">No activity recorded in this range yet. Statistics start from when this dashboard was installed; earlier history isn\\'t available.</p>');
  const charts = document.getElementById("charts");
  charts.append(chartCard(days, "registrations", { label: "Registrations" }));
  charts.append(chartCard(days, "dau", { label: "Daily active accounts", total: "max", totalLabel: "busiest day" }));
  charts.append(chartCard(days, "runs.started", { label: "Account digs started" }));
  charts.append(chartCard(days, "play_seconds", { label: "Play time (hours, estimate)", scale: 3600, unit: " h", note: "Foreground time in digs reported by the game; not proof of play." }));
  const logins = sums(days, "login.");
  const methodRows = Object.keys(METHODS).filter((m) => logins[m + ".success"] || logins[m + ".failure"] || logins[m + ".challenge"]).map((m) => [METHODS[m], num(logins[m + ".success"]), num(logins[m + ".failure"]), num(logins[m + ".challenge"])]);
  const platforms = sums(days, "runs.platform."), versions = sums(days, "runs.version."), diggers = sums(days, "runs.character."), errors = sums(days, "sync.error.");
  const total = (k) => days.reduce((a, d) => a + (d.metrics[k] || 0), 0);
  const deepest = Math.max(0, ...days.map((d) => d.metrics["runs.deepest"] || 0));
  document.getElementById("tables").innerHTML =
    table("Logins", ["Method", "Succeeded", "Failed", "Awaiting code"], methodRows) +
    table("Account digs", ["Measure", "Count"], total("runs.started") || total("runs.finished") ? [["Started", num(total("runs.started"))], ["Results recorded (once each)", num(total("runs.finished"))], ["Wins", num(total("runs.wins"))], ["Left early", num(total("runs.abandoned"))], ["Deepest descent", deepest ? String(deepest) : "—"]] : []) +
    table("Digger usage (results)", ["Digger", "Digs"], Object.entries(diggers).sort((a, b) => b[1] - a[1]).map(([k, v]) => [DIGGERS[k] || "Digger " + k, num(v)])) +
    table("Platforms (digs started, self-reported)", ["Platform", "Digs"], Object.entries(platforms).sort((a, b) => b[1] - a[1]).map(([k, v]) => [k, num(v)])) +
    table("Game protocol versions", ["Version", "Digs"], Object.entries(versions).sort((a, b) => b[0] - a[0]).map(([k, v]) => ["v" + k, num(v)])) +
    table("Sync reliability", ["Measure", "Count"], [...Object.entries(errors).sort((a, b) => b[1] - a[1]).map(([k, v]) => ["Refused/failed: " + k, num(v)]), ["Safe retries (replayed, not double-counted)", num(total("sync.replays"))]]);
}

async function loadUsers() {
  const list = document.getElementById("list");
  list.innerHTML = '<p>Loading players…</p>';
  const r = await get("/api/admin/users?q=" + encodeURIComponent(state.q) + "&page=" + state.page);
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) return gate(r);
    list.innerHTML = '<p class="bad">' + esc(r.data?.error?.message || "Players are unavailable right now.") + '</p>';
    return;
  }
  const d = r.data;
  const pages = Math.max(1, Math.ceil(d.total / d.page_size));
  if (!d.users.length) { list.innerHTML = '<p class="muted">' + (state.q ? "No players match that search." : "No accounts yet.") + '</p>'; return; }
  list.innerHTML = '<table><thead><tr><th>Name</th><th>Email</th><th>Verified</th><th>Registered</th><th>Last sign-in</th><th>Last active</th><th>Last platform</th></tr></thead><tbody>' +
    d.users.map((u) => '<tr class="pick" tabindex="0" data-id="' + esc(u.id) + '"><td>' + esc(u.name) + (u.role === "admin" ? ' <span class="muted">(owner)</span>' : "") + '</td><td>' + esc(u.email) + '</td><td>' + (u.verified ? "Yes" : "No") + '</td><td>' + when(u.registered_at) + '</td><td>' + when(u.last_login_at) + '</td><td>' + when(u.last_active_at) + '</td><td>' + esc(u.platform || "—") + '</td></tr>').join("") +
    '</tbody></table><div class="row"><button class="secondary" id="prev"' + (d.page <= 1 ? " disabled" : "") + '>Previous</button><span class="muted">Page ' + d.page + ' of ' + pages + ' · ' + num(d.total) + ' players</span><button class="secondary" id="next"' + (d.page >= pages ? " disabled" : "") + '>Next</button></div>';
  document.getElementById("prev").onclick = () => { state.page--; loadUsers(); };
  document.getElementById("next").onclick = () => { state.page++; loadUsers(); };
  list.querySelectorAll("tr.pick").forEach((tr) => { tr.onclick = () => loadUser(tr.dataset.id); tr.onkeydown = (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); loadUser(tr.dataset.id); } }; });
}

async function loadUser(id) {
  const box = document.getElementById("detail");
  box.innerHTML = '<p>Loading player…</p>';
  const r = await get("/api/admin/users/" + encodeURIComponent(id));
  if (!r.ok) {
    if (r.status === 401 || r.status === 403) return gate(r);
    box.innerHTML = '<p class="bad">' + esc(r.data?.error?.message || "That player couldn't be loaded.") + '</p>';
    return;
  }
  const u = r.data, p = u.profile, s = u.sync;
  box.innerHTML = '<h2 tabindex="-1" id="who">' + esc(u.name) + '</h2><div class="grid2"><div><h3>Account</h3><dl>' +
    '<dt>Account id</dt><dd>' + esc(u.id) + '</dd><dt>Email</dt><dd>' + esc(u.email) + '</dd><dt>Verified</dt><dd>' + (u.verified ? "Yes" : "No") + '</dd><dt>Role</dt><dd>' + esc(u.role) + '</dd><dt>Authenticator</dt><dd>' + (u.two_factor ? "On" : "Off") + '</dd>' +
    '<dt>Registered</dt><dd>' + when(u.registered_at) + '</dd><dt>Last sign-in</dt><dd>' + when(u.last_login_at) + '</dd><dt>Active sessions</dt><dd>' + num(u.active_sessions) + '</dd><dt>Last active day</dt><dd>' + esc(u.last_active_at || "—") + '</dd></dl></div>' +
    '<div><h3>Progress</h3><dl><dt>Digs</dt><dd>' + num(p.runs) + '</dd><dt>Wins</dt><dd>' + num(p.wins) + '</dd><dt>Machines</dt><dd>' + num(p.kills) + '</dd><dt>Zenny</dt><dd>' + num(p.zenny) + '</dd><dt>Circuits bought</dt><dd>' + num(p.circuits) + '</dd><dt>Parts discovered</dt><dd>' + num(p.discovered) + '</dd><dt>Revision</dt><dd>' + num(p.revision) + '</dd><dt>Last change</dt><dd>' + when(p.updated_at) + '</dd>' + (p.adopted_at ? '<dt>Guest adopted</dt><dd>' + when(p.adopted_at) + '</dd>' : "") + '</dl></div>' +
    '<div><h3>Sync health (30 days)</h3><dl><dt>Refused/failed calls</dt><dd>' + num(s.errors_30d) + '</dd><dt>Safe retries</dt><dd>' + num(s.replays_30d) + '</dd><dt>Last problem</dt><dd>' + when(s.last_error_at) + '</dd><dt>Last saved operation</dt><dd>' + when(s.last_operation_at) + '</dd></dl></div></div>' +
    table("Recent digs", ["Started", "Platform", "Version", "Status"], u.runs.map((x) => [when(x.started_at), x.platform, "v" + x.game_version, x.status]), "No account digs yet.") +
    table("Activity (last 30 active days)", ["UTC day", "Play time", "Platforms"], u.activity.map((a) => [a.day, Math.round(a.seconds / 60) + " min", a.platforms.join(", ") || "—"]), "No activity recorded in the last 90 days.");
  document.getElementById("who").focus();
}

async function start() {
  const me = await get("/api/admin/me");
  if (!me.ok) return gate(me);
  layout();
  loadStats();
  loadUsers();
}
start();
`;

export function adminPage(res) {
  res.writeHead(200, { ...HEADERS, "Content-Type": "text/html; charset=utf-8" });
  res.end(PAGE);
}
export function adminAsset(res, name) {
  const js = name === "app.js";
  res.writeHead(200, { ...HEADERS, "Content-Type": js ? "text/javascript; charset=utf-8" : "text/css; charset=utf-8", "Cache-Control": "no-cache" });
  res.end(js ? JS : CSS);
}
