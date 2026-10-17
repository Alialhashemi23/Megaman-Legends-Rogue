// One coordinated heavy job: disposable PostgreSQL/API/relay plus real Edge
// clients. Export tests/ui02_browser_driver.tscn as the test-only Web entry point.
// Fixture commands only seed earned events/observe state; picks and close use
// actual keyboard/mouse input. Production export presets exclude this driver.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createServer } from '../server/server.js';
import { createAccounts } from '../server/accounts/api.js';
import { createPool, migrate } from '../server/accounts/db.js';
import { authOptions } from '../server/accounts/auth.js';
import { createMailer } from '../server/accounts/mail.js';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'save', `ui02-browser-${Date.now()}`);
fs.mkdirSync(out, { recursive: true });
const container = `relic-ui02-test-${process.pid}`;
const docker = (...args) => execFileSync('docker', args, { encoding: 'utf8', stdio: ['ignore','pipe','pipe'] }).trim();
const pause = ms => new Promise(r => setTimeout(r, ms));
const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
let pool, accounts, app, testContainer = false;
const browsers = [], pages = [], errors = [];
const mail = [], secret = crypto.randomBytes(32).toString('hex');
const probe = createServer({ port: 0, log: () => {} });
const port = await probe.listen(); await probe.close();
const base = `http://127.0.0.1:${port}`;
async function call(route, body) {
  const response = await fetch(base + route, { method: 'POST', headers: { Origin: base, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await response.json(); assert.ok(response.ok, `${route}: ${response.status} ${JSON.stringify(data)}`); return data;
}
async function open(label, width = 960, height = 600) {
  const browser = await chromium.launch({ executablePath: process.env.E2E_BROWSER_EXECUTABLE, args: ['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required','--disable-renderer-backgrounding','--disable-background-timer-throttling','--disable-backgrounding-occluded-windows'] });
  browsers.push(browser);
  const context = await browser.newContext({ viewport: { width, height } });
  const page = await context.newPage(); pages.push(page); page.label = label;
  page.on('pageerror', e => errors.push(`${label}: ${e.message}`));
  page.on('console', m => {
    if (/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text())) errors.push(`${label}: ${m.text()}`);
    if (/ONLINE:|ERROR:/.test(m.text())) console.log(`[${label}] ${m.text()}`);
  });
  await page.goto(base, { waitUntil: 'domcontentloaded' });
  await until(page, s => s.mode === 'title', 'engine/title');
  return page;
}
const state = page => page.evaluate(() => structuredClone(window.ui02State));
const command = (page, request) => page.evaluate(value => window.ui02Command(JSON.stringify(value)), request);
async function until(page, condition, label) {
  try { await page.waitForFunction(`window.ui02State && (${condition.toString()})(window.ui02State)`, null, { timeout: 90000 }); }
  catch (error) { console.log('WAIT FAILED', page.label, label, await state(page).catch(()=>null)); throw error; }
}
const shot = (page, name) => page.screenshot({ path: path.join(out, name + '.png') });
async function button(page, action, hold = false) {
  const s = await state(page), hit = s.buttons.find(b => b.action === action);
  assert.ok(hit, `Missing ${action} in ${s.mode}`);
  const view = page.viewportSize();
  await page.mouse.move(hit.x * view.width, hit.y * view.height);
  await page.mouse.down(); if (!hold) await page.mouse.up();
}
async function capture(page) {
  if (!(await page.evaluate(() => Boolean(document.pointerLockElement)))) {
    const view = page.viewportSize(); await page.mouse.click(view.width / 2, view.height / 2);
  }
  await page.waitForFunction(() => document.pointerLockElement !== null, null, { timeout: 15000 });
}
async function reload(page) {
  await page.reload({ waitUntil: 'domcontentloaded' });
  await until(page, s => s.signed && s.confirmed && s.mode === 'play' && !s.waiting_sync, 'authenticated rejoin');
}
try {
  docker('run','--detach','--rm','--name',container,'--label','relic.test=ui02','-e','POSTGRES_USER=relic','-e','POSTGRES_DB=ui02','-e','POSTGRES_PASSWORD=ui02-disposable-only','-p','127.0.0.1::5432','postgres:17.11-alpine'); testContainer = true;
  const mapped = docker('port',container,'5432/tcp').split(':').at(-1);
  pool = createPool(`postgres://relic:ui02-disposable-only@127.0.0.1:${mapped}/ui02`, () => {});
  let ready = false;
  for (let attempt = 0; attempt < 60; attempt++) { try { await pool.query('select 1'); ready = true; break; } catch { await pause(500); } }
  assert.ok(ready, 'Disposable database started');
  await migrate(pool, authOptions({ pool, secret, origin: base, mailer: createMailer({ sink: mail }) }), () => {});
  accounts = await createAccounts({ pool, secret, origin: base, mailSink: mail, rateLimit: false, apiLimits: { ip: 100000, account: 100000 }, log: () => {} });
  app = createServer({ port, accounts, webRoot: path.join(root,'build/ui02-web'), log: m => console.log('[relay]',m) }); await app.listen();

  // Solo: same camera/world, paused clock; real Later press cannot leak fire.
  const solo = await open('solo');
  await command(solo,{op:'solo'}); await until(solo,s=>s.mode==='play','solo start');
  await command(solo,{op:'protect'}); await pause(500);
  const before = await state(solo);
  await command(solo,{op:'cache'}); await until(solo,s=>s.mode==='choice' && s.choice_ready,'solo cache');
  const frozen = await state(solo); await pause(800); const still = await state(solo);
  assert.equal(still.time,frozen.time); assert.deepEqual(still.pos,frozen.pos); assert.deepEqual(still.camera,frozen.camera);
  const offered = frozen.pending;
  await shot(solo,'01-solo-overlay-960x600');
  await button(solo,'choice_later',true); await until(solo,s=>s.mode==='play','Later closes');
  await pause(500); assert.equal((await state(solo)).shots,before.shots,'Held Later click cannot fire');
  await solo.mouse.up(); await until(solo,s=>!s.guard,'release restores actions');
  await capture(solo);
  await solo.keyboard.down('KeyW'); await pause(450); await solo.keyboard.up('KeyW');
  assert.ok((await state(solo)).pos.some((v,i)=>Math.abs(v-frozen.pos[i])>0.1),'Movement restored');
  await solo.mouse.down(); await pause(400); await solo.mouse.up();
  assert.ok((await state(solo)).shots>before.shots,'Fresh mouse press fires');
  await solo.keyboard.press('Tab'); await until(solo,s=>s.mode==='choice','reopen');
  assert.deepEqual((await state(solo)).pending,offered,'Reopen keeps exact offer');
  await solo.keyboard.press('Escape'); await until(solo,s=>s.mode==='play','Escape closes'); await capture(solo);
  await shot(solo,'02-solo-after-close');
  await browsers[0].close();
  console.log('SOLO_WEB_PASS: pause, camera, Later/held click, Escape, recapture, movement/fire, exact offers');

  const credentials = [];
  for (const name of ['Host','Guest']) {
    const email = `ui02-${name.toLowerCase()}-${Date.now()}@example.test`, password = 'ui02 disposable password';
    await call('/api/auth/sign-up/email',{name:'Overlay '+name,email,password});
    const verification = mail.find(m=>m.to===email && m.kind==='verify'); assert.ok(verification);
    await fetch(verification.url,{redirect:'manual'}); credentials.push({email,password});
  }
  const host = await open('host',720,450), guest = await open('guest');
  for (const [i,page] of [host,guest].entries()) { await command(page,{op:'sign_in',...credentials[i]}); await until(page,s=>s.signed && s.source==='account','real email/password sign-in'); }
  await command(host,{op:'create'}); await until(host,s=>s.mode==='lobby' && s.confirmed,'account lobby create');
  const code = (await state(host)).code;
  await command(guest,{op:'join',code}); await until(guest,s=>s.mode==='lobby' && s.confirmed,'account lobby join');
  await until(host,s=>s.acked,'host loadout ack'); await until(guest,s=>s.acked,'guest loadout ack'); await pause(700);
  await command(host,{op:'ready'}); await until(host,s=>s.ready,'host Ready'); await pause(300);
  await command(guest,{op:'ready'}); await until(guest,s=>s.ready,'guest Ready'); await until(host,s=>s.can_start,'confirmed party');
  await command(host,{op:'start'}); await until(host,s=>s.mode==='play','host commit'); await until(guest,s=>s.mode==='play','guest commit');
  const hs = await state(host), gs = await state(guest);
  assert.equal(hs.run,gs.run); assert.equal(hs.seed,gs.seed);
  assert.ok(hs.player_id.startsWith('acct:') && gs.player_id.startsWith('acct:') && hs.account_run && gs.account_run,'Real account tickets and run leases');
  await command(host,{op:'protect'}); await command(guest,{op:'protect'});
  await command(host,{op:'cache'}); await until(guest,s=>s.pending.length===1,'shared cache event');
  await command(host,{op:'xp'}); await until(guest,s=>s.pending.length===2,'shared level event');
  await command(host,{op:'cache'}); await until(guest,s=>s.pending.length===3,'second shared cache');
  await command(host,{op:'milestone'}); await until(guest,s=>s.pending.length===4,'shared guardian event');
  assert.deepEqual((await state(guest)).pending.map(p=>p.kind),['relic','level','relic','milestone']);
  assert.equal((await state(guest)).mode,'play','Earned co-op offers do not auto-open');
  await capture(guest); await guest.keyboard.press('Tab'); await until(guest,s=>s.mode==='choice' && s.choice_ready,'manual queue open');
  const openState = await state(guest);
  await guest.keyboard.down('KeyW'); await pause(500); await guest.keyboard.up('KeyW');
  const during = await state(guest); assert.ok(during.time>openState.time,'Co-op clock continues'); assert.deepEqual(during.pos,openState.pos,'Chooser cannot move');
  await shot(guest,'03-authenticated-coop-four-offers');
  const firstPart = openState.pending[0].items[0];
  await guest.keyboard.down('Digit1'); await until(guest,s=>s.choice_picks===1,'first pick'); await pause(700);
  assert.equal((await state(guest)).choice_picks,1,'Held key cannot take next offer'); await guest.keyboard.up('Digit1');
  await until(guest,s=>s.choice_ready,'fresh confirm armed');
  await guest.keyboard.press('Escape'); await until(guest,s=>s.mode==='play' && s.pending.length===3,'close level');
  const deferred = await state(guest);
  await until(host,s=>Object.values(s.peers).some(p=>p.length===3),'peer recovery build after B');
  assert.deepEqual((await state(host)).peers[gs.player_id],deferred.pending,'Peer holds exactly the three unapplied offers');
  await command(guest,{op:'save'}); await command(host,{op:'save'}); await pause(1000);
  await reload(guest);
  let recovered = await state(guest);
  assert.deepEqual(recovered.pending,deferred.pending,'Reload after B preserves exact offers');
  assert.equal(recovered.items[firstPart],1,'First reward applied exactly once');
  const damage = recovered.damage;
  await guest.keyboard.press('Tab'); await until(guest,s=>s.mode==='choice' && s.choice_ready,'reopen level');
  await guest.keyboard.down('Digit1'); await until(guest,s=>s.choice_picks===1,'level selected'); await pause(600);
  assert.equal((await state(guest)).damage,damage+1,'Held confirm gives one stat gain'); await guest.keyboard.up('Digit1');
  await until(guest,s=>s.choice_ready,'part input armed'); await guest.keyboard.press('Digit1');
  await until(guest,s=>s.choice_picks===2 && s.choice_kind==='milestone' && s.choice_ready,'sequential milestone');
  await shot(guest,'04-authenticated-coop-milestone');
  await guest.keyboard.press('Digit1'); await until(guest,s=>s.mode==='play' && s.pending.length===0,'final pick');
  const complete = await state(guest);
  await until(host,s=>s.peers[Object.keys(s.peers).find(k=>k!==s.player_id)]?.length===0,'peer final-pick build');
  assert.deepEqual((await state(host)).peers[gs.player_id],[],'Final selection publishes no phantom offer');
  await command(guest,{op:'save'}); await command(host,{op:'save'}); await pause(1000);
  await reload(guest); recovered = await state(guest);
  assert.deepEqual(recovered.pending,[]); assert.deepEqual(recovered.items,complete.items); assert.equal(recovered.damage,complete.damage); assert.deepEqual(recovered.milestones,complete.milestones);
  await shot(guest,'05-authenticated-rejoin-no-duplicate');
  // Account cookies and relay identity also survive host reload/migration.
  const hostWaiting = (await state(host)).pending;
  assert.equal(hostWaiting.length,4,'Host still has four unapplied offers');
  await reload(host); await until(guest,s=>s.host,'host migration');
  assert.deepEqual((await state(host)).pending,hostWaiting,'Host migration preserves its exact unapplied queue');
  assert.deepEqual((await state(guest)).pending,[]); assert.equal((await state(guest)).damage,damage+1);
  const activeRuns = await pool.query("select count(*)::int as count from game_run where status='active'");
  assert.equal(activeRuns.rows[0].count,2,'One active account run per digger');
  assert.deepEqual(errors,[]);
  console.log('UI02_WEB_E2E_PASS: real account sign-in/tickets/leases, four queued offers, held input, B/reload, sequential picks, final-pick/reload, host migration; no rerolls/loss/duplicate rewards');
  console.log('CAPTURES',out);
} catch(error) {
  for(const page of pages) if(!page.isClosed()) {
    await shot(page,`failure-${page.label}`).catch(()=>{});
    fs.writeFileSync(path.join(out,`failure-${page.label}.json`),JSON.stringify(await state(page).catch(()=>null),null,2));
  }
  throw error;
} finally {
  for(const browser of browsers) await browser.close().catch(()=>{});
  await app?.close(); await accounts?.close(); await pool?.end();
  if(testContainer) docker('rm','--force',container);
}
