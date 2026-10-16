// Local-only integration: real PostgreSQL/API, Godot HTTP transport, optional
// browser game. Requires TEST_DATABASE_URL, GODOT and (for web) PLAYWRIGHT_MODULE.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import pg from '../server/node_modules/pg/lib/index.js';
import { createServer } from '../server/server.js';
import { createAccounts } from '../server/accounts/api.js';
import { createPool, migrate } from '../server/accounts/db.js';
import { authOptions } from '../server/accounts/auth.js';
import { createMailer } from '../server/accounts/mail.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const adminUrl = process.env.TEST_DATABASE_URL;
assert.ok(adminUrl && process.env.GODOT, 'Set TEST_DATABASE_URL and GODOT');
const db = `relic_sync_${process.pid}_${Date.now()}`;
const admin = new pg.Client({ connectionString: adminUrl });
await admin.connect();
await admin.query(`create database ${db}`);
const pool = createPool(adminUrl.replace(/\/[^/]*$/, `/${db}`), () => {});
const mail = [];
const secret = crypto.randomBytes(32).toString('hex');
let app, accounts, browser, lastPage;
const drops = new Set(['/api/v1/run-results', '/api/v1/purchases']);
// Forward to the API, then lose the first committed response on each write.
// Native Godot alone uses this proxy; browser traffic goes directly to the API.
const proxy = http.createServer(async (req, res) => {
  const body = [];
  for await (const chunk of req) body.push(chunk);
  const headers = { ...req.headers }; delete headers.host;
  // Like the public tunnel, the proxy is the server's own origin to the game.
  if (headers.origin === proxyBase) headers.origin = base;
  try {
    const upstream = await fetch(base + req.url, { method: req.method, headers, body: req.method === 'GET' ? undefined : Buffer.concat(body) });
    const bytes = Buffer.from(await upstream.arrayBuffer());
    if (upstream.ok && drops.delete(req.url)) return res.destroy();
    res.writeHead(upstream.status, Object.fromEntries(upstream.headers)); res.end(bytes);
  } catch { res.writeHead(503); res.end('{}'); }
});
// Forward WebSocket upgrades without altering the relay protocol.
const { default: net } = await import('node:net');
proxy.on('upgrade', (req, socket, head) => {
  const upstream = net.connect(port, '127.0.0.1', () => {
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n${req.rawHeaders.reduce((s, h, i) => s + (i % 2 ? `${h}\r\n` : `${h}: `), '')}\r\n`);
    if (head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on('error', () => socket.destroy()); socket.on('error', () => upstream.destroy());
});
await new Promise(resolve => proxy.listen(0, '127.0.0.1', resolve));
const probe = createServer({ port: 0, log: () => {} });
const port = await probe.listen(); await probe.close();
const base = `http://127.0.0.1:${port}`;
const proxyBase = `http://127.0.0.1:${proxy.address().port}`;

async function call(route, body, token) {
  const r = await fetch(base + route, { method: body ? 'POST' : 'GET', headers: { Origin: base, ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const data = await r.json(); assert.ok(r.ok, `${route}: ${r.status} ${JSON.stringify(data)}`);
  return { data, headers: r.headers };
}
// Authenticator codes (RFC 6238, SHA-1, 6 digits, 30 s) from the setup secret.
let lastStep = -1;
function totp(secret, step) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bits = [...secret.replace(/=+$/, '').toUpperCase()].map(c => alphabet.indexOf(c).toString(2).padStart(5, '0')).join('');
  const key = Buffer.from(bits.match(/.{8}/g).map(b => parseInt(b, 2)));
  const counter = Buffer.alloc(8); counter.writeBigUInt64BE(BigInt(step));
  const h = crypto.createHmac('sha1', key).update(counter).digest();
  const o = h[h.length - 1] & 15;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1e6).padStart(6, '0');
}
// A code from a step not used before, with at least 12 s left to type it.
async function freshCode(secret) {
  for (;;) {
    const now = Date.now(), step = Math.floor(now / 30000), left = 30000 - (now % 30000);
    if (step !== lastStep && left > 12000) { lastStep = step; return totp(secret, step); }
    await new Promise(r => setTimeout(r, left + 300));
  }
}
// The native game signs in itself through the in-game panel, then syncs.
async function native(mode, credentials, expected = 217) {
  const child = spawn(process.env.GODOT, ['--headless', '--path', root, '--script', 'tests/account_http_driver.gd'], {
    cwd: root, env: { ...process.env, APPDATA: path.join(root, 'tools/runtime'), LOCALAPPDATA: path.join(root, 'tools/runtime'), ACCOUNT_TEST_ORIGIN: proxyBase, ACCOUNT_TEST_EMAIL: credentials.email, ACCOUNT_TEST_PASSWORD: credentials.password, ACCOUNT_TEST_TOTP: credentials.secret ? await freshCode(credentials.secret) : '', ACCOUNT_TEST_ZENNY: String(expected), ACCOUNT_TEST_MODE: mode, ACCOUNT_TEST_CACHE: `user://account-e2e-${db}-${mode}` }, stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = ''; child.stdout.on('data', b => output += b); child.stderr.on('data', b => output += b);
  const timer = setTimeout(() => child.kill(), 120000);
  const code = await new Promise(resolve => child.once('exit', resolve)); clearTimeout(timer);
  process.stdout.write(output.replaceAll(credentials.password, '[redacted]'));
  assert.equal(code, 0, `Native ${mode} integration failed`);
}
try {
  await migrate(pool, authOptions({ pool, secret, origin: base, mailer: createMailer({ sink: mail }) }), () => {});
  accounts = await createAccounts({ pool, secret, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 100000, account: 100000 }, log: () => {} });
  app = createServer({ port, accounts, webRoot: path.join(root, 'build/web'), log: () => {} }); await app.listen();
  const email = `sync-${db}@example.test`, password = 'account test password';
  await call('/api/auth/sign-up/email', { name: 'Sync Digger', email, password });
  const verification = mail.find(m => m.to === email && m.kind === 'verify');
  assert.ok(verification); await fetch(verification.url, { redirect: 'manual' });
  const signed = await call('/api/auth/sign-in/email', { email, password });
  const token = signed.headers.get('set-auth-token'); assert.ok(token);
  const profile = { version: 2, kills: 0, runs: 0, wins: 0, deepest: 0, best_time: 0, zenny: 200, discovered: {}, trees: {}, legacy_unlocks: [] };
  const preview = await call('/api/v1/migrate-guest', { profile }, token);
  await call('/api/v1/migrate-guest', { op_id: crypto.randomUUID(), profile, confirm: preview.data.confirm }, token);
  const credentials = { email, password };
  await native('write', credentials); await native('read', credentials);
  const confirmed = (await call('/api/v1/profile', null, token)).data;
  assert.equal(confirmed.profile.zenny, 217); assert.equal(confirmed.profile.runs, 1);
  assert.equal(drops.size, 0, 'Lost responses exercised both results and purchases');
  // Turn on an authenticator, like the owner's account: sign-ins now need a code.
  const enabled = await call('/api/auth/two-factor/enable', { password }, token);
  credentials.secret = new URL(enabled.data.totpURI).searchParams.get('secret');
  const turnedOn = await call('/api/auth/two-factor/verify-totp', { code: await freshCode(credentials.secret) }, token);
  const session = turnedOn.headers.get('set-auth-token') || token;
  await native('read', credentials);
  if (process.env.PLAYWRIGHT_MODULE) {
    const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
    browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
    for (let i = 0; i < 2; i++) {
      const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
      const page = await context.newPage(); const errors = [];
      lastPage = page;
      page.on('pageerror', e => errors.push(e.message));
      page.on('console', m => { if (/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text())) errors.push(m.text()); });
      await page.goto(`${base}/?lobby=SYNCINVITE`);
      await page.locator('#loader').waitFor({ state: 'hidden', timeout: 120000 });
      await page.waitForTimeout(2500);
      const click = async (x, y) => { await page.mouse.click(x * 1280 / 1440, y * 800 / 900); await page.waitForTimeout(500); };
      // The invite opens the in-game sign-in panel; nothing leaves this page.
      await click(720, 324); await page.keyboard.type(email);
      await click(720, 410); await page.keyboard.type(password);
      await click(720, 481);
      await page.waitForTimeout(3000);
      await click(720, 324); await page.keyboard.type(await freshCode(credentials.secret));
      await click(720, 397);
      await page.waitForFunction(() => Object.keys(localStorage).some(k => k.startsWith('relicAccount:') && k.endsWith(':profile.json')), null, { timeout: 30000 });
      await page.waitForTimeout(1500);
      assert.equal(new URL(page.url()).pathname, '/'); assert.equal(new URL(page.url()).searchParams.get('lobby'), 'SYNCINVITE');
      assert.equal(await page.evaluate(() => crossOriginIsolated), true);
      const cache = await page.evaluate(() => Object.entries(localStorage).filter(([k]) => k.startsWith('relicAccount:') && k.endsWith(':profile.json')).map(([, v]) => JSON.parse(v)));
      assert.equal(cache[0]?.profile.zenny, i === 0 ? 217 : 77, 'Browser game loaded same confirmed wallet');
      assert.equal(cache[0]?.profile.trees['0'][0], 'frame');
      if (i === 0) {
        // Back navigation does not depend on last frame's mouse hit targets.
        await page.keyboard.press('Escape');
        await page.waitForTimeout(1500);
        await click(300, 874); // Workshop.
        await page.waitForTimeout(1000);
        await click(692, 481); // Lightweight Joints (mobility), linked from the confirmed Frame.
        await page.waitForFunction(() => Object.entries(localStorage).some(([k, v]) => k.startsWith('relicAccount:') && k.endsWith(':profile.json') && JSON.parse(v).profile.zenny === 77), null, { timeout: 20000 });
        const stillSignedIn = page.waitForResponse(r => r.url().endsWith('/api/v1/profile') && r.status() === 200, { timeout: 120000 });
        await page.reload();
        await stillSignedIn; // The session cookie survives a reload.
        await page.locator('#loader').waitFor({ state: 'hidden', timeout: 120000 });
        await page.waitForTimeout(2000);
        const cloud = (await call('/api/v1/profile', null, session)).data;
        assert.equal(cloud.profile.zenny, 77); assert.ok(cloud.profile.trees['0'].includes('mobility'));
      }
      assert.equal(errors.length, 0, errors.join('\n'));
      await context.close();
    }
    await native('read', credentials, 77);
  }
  console.log(`ACCOUNT_E2E: real API, in-game password and authenticator sign-in, lost responses, native cross-device and signed-in relay passed${browser ? '; browser in-game sign-in/invite, purchase, reload and cross-device sync passed' : ''}`);
} catch (error) {
  if (lastPage && !lastPage.isClosed()) await lastPage.screenshot({ path: path.join(root, 'tools/account-browser-failure.png') });
  throw error;
} finally {
  await browser?.close(); await app?.close(); await accounts?.close();
  proxy.closeAllConnections(); await new Promise(resolve => proxy.close(resolve));
  await pool.end(); await admin.query(`drop database if exists ${db} with (force)`); await admin.end();
}
