// Real exported Workshop UI/input in temporary browser contexts, controlled
// account transport replies. No production accounts or backend API changes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createServer } from '../server/server.js';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const shots = path.join(root,'save',`ui03-browser-${Date.now()}`);
fs.mkdirSync(shots,{recursive:true});
const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app = createServer({port:0,webRoot:path.join(root,'build/ui03-web'),log:()=>{}});
const port = await app.listen();
const browser = await chromium.launch({executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
const pages=[], errors=[];
async function until(page,predicate,label) {
  try { await page.waitForFunction(`window.ui03State && (${predicate.toString()})(window.ui03State)`,null,{timeout:60000}); }
  catch(error) { console.log('FAILED',label,await state(page).catch(()=>null)); throw error; }
}
const state = page=>page.evaluate(()=>structuredClone(window.ui03State));
const command = (page,value)=>page.evaluate(v=>window.ui03Command(JSON.stringify(v)),value);
const shot = (page,name)=>page.screenshot({path:path.join(shots,name+'.png')});
async function open(label) {
  const context=await browser.newContext({viewport:{width:960,height:600}});
  const page=await context.newPage(); page.label=label; pages.push(page);
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
  await page.goto(`http://127.0.0.1:${port}`,{waitUntil:'domcontentloaded'});
  await until(page,s=>s.mode==='workshop' && s.buttons.length>0 && s.requests===0,'Workshop ready');
  return page;
}
async function click(page,action,value=0,count=1) {
  const s=await state(page),hit=s.buttons.find(b=>b.action===action && b.value===value);
  assert.ok(hit,`${action}:${value} missing in ${s.mode}`);
  const view=page.viewportSize();
  await page.mouse.click(hit.x*view.width,hit.y*view.height,{clickCount:count});
}
async function review(page,value=0) {
  await click(page,'grid_node',value);
  await until(page,s=>s.mode==='purchase_review' && s.buttons.some(b=>b.action==='purchase_cancel'),'review');
  assert.equal((await state(page)).focus,'purchase_cancel');
}
try {
  const guest=await open('guest');
  await review(guest);
  assert.equal((await state(guest)).wallet,500);
  assert.deepEqual((await state(guest)).trees,{});
  await guest.setViewportSize({width:1440,height:900}); await guest.waitForTimeout(400);
  await shot(guest,'01-guest-review-1440x900');
  await guest.setViewportSize({width:960,height:540}); await guest.waitForTimeout(400);
  await shot(guest,'02-guest-review-960x540');
  await guest.keyboard.press('Enter'); await until(guest,s=>s.mode==='workshop','default Cancel');
  assert.equal((await state(guest)).wallet,500); assert.equal((await state(guest)).focus,'grid_node');
  await review(guest); await guest.keyboard.press('Escape'); await until(guest,s=>s.mode==='workshop','Escape cancel');
  assert.equal((await state(guest)).wallet,500);
  await review(guest); await until(guest,s=>s.ready,'fresh input');
  await guest.keyboard.press('ArrowRight'); assert.equal((await state(guest)).wallet,500);
  await guest.keyboard.down('Enter'); await until(guest,s=>s.review.phase==='confirmed','Guest purchase');
  await guest.keyboard.down('Enter'); await guest.waitForTimeout(400); await guest.keyboard.up('Enter');
  assert.equal((await state(guest)).wallet,400); assert.deepEqual((await state(guest)).trees['0'],['frame']);
  await shot(guest,'03-guest-confirmed');
  await guest.keyboard.press('Escape'); await until(guest,s=>s.mode==='workshop','receipt close');
  await click(guest,'grid_node'); assert.equal((await state(guest)).mode,'workshop'); assert.equal((await state(guest)).wallet,400);
  await guest.context().close();
  console.log('GUEST_WEB_PASS: Cancel default, mouse selection, B, fresh/held Confirm, one charge and ownership');

  const failed=await open('guest-write-failure');
  await command(failed,{op:'block_save'}); await review(failed); await until(failed,s=>s.ready,'storage input');
  await click(failed,'purchase_confirm'); await until(failed,s=>s.review.phase==='refused','write refusal');
  assert.equal((await state(failed)).wallet,500); assert.deepEqual((await state(failed)).trees,{});
  await shot(failed,'04-guest-write-failure'); await failed.context().close();

  const cloud=await open('account');
  await command(cloud,{op:'cloud'}); await until(cloud,s=>s.source==='account' && s.status==='Synced','mock confirmed account');
  await review(cloud); await until(cloud,s=>s.ready,'account input'); await click(cloud,'purchase_confirm',0,2);
  await until(cloud,s=>s.review.phase==='pending' && s.status==='Offline','lost response');
  let s=await state(cloud); const operation=s.review.op_id;
  assert.equal(s.wallet,500); assert.equal(s.pending,1); assert.equal(s.sent.length,1);
  assert.ok(!s.buttons.some(b=>b.action==='purchase_cancel'));
  await shot(cloud,'05-account-pending-offline');
  await cloud.keyboard.press('Escape'); await until(cloud,s=>s.mode==='workshop','pending close');
  assert.equal((await state(cloud)).pending,1);
  await click(cloud,'grid_node'); await until(cloud,s=>s.mode==='purchase_review' && s.focus==='purchase_close','pending reopen');
  assert.equal((await state(cloud)).review.op_id,operation);
  await command(cloud,{op:'reply',value:'success'}); await click(cloud,'purchase_retry',0,2);
  await until(cloud,s=>s.review.phase==='confirmed' && s.pending===0,'retry confirmation');
  s=await state(cloud); assert.equal(s.wallet,400); assert.deepEqual(s.trees['0'],['frame']);
  assert.ok(s.sent.length>=2 && s.sent.every(id=>id===operation),'Retry reuses the existing operation');
  await shot(cloud,'06-account-confirmed'); await cloud.context().close();

  const conflict=await open('account-conflict');
  await command(conflict,{op:'cloud'}); await until(conflict,s=>s.source==='account' && s.status==='Synced','conflict account');
  await command(conflict,{op:'reply',value:'conflict'}); await review(conflict); await until(conflict,s=>s.ready,'conflict input');
  await click(conflict,'purchase_confirm'); await until(conflict,s=>s.review.phase==='refused','revision conflict');
  s=await state(conflict); assert.equal(s.wallet,270); assert.deepEqual(s.trees['0'],['frame']); assert.equal(s.pending,0);
  assert.ok(s.review.note.includes('another device'));
  await shot(conflict,'07-account-revision-conflict'); await conflict.context().close();
  console.log('ACCOUNT_UI_WEB_PASS: actual outbox with mocked lost response/retry/conflict, same op_id, accurate wallet and ownership');

  const special=await open('specialization');
  await command(special,{op:'specialization'}); await special.waitForTimeout(400);
  await review(special,12); s=await state(special);
  assert.equal(s.review.character,2); assert.equal(s.review.name,'Siege Breaker'); assert.equal(s.review.cost,600);
  await special.setViewportSize({width:1440,height:900}); await special.waitForTimeout(300);
  await shot(special,'08-specialization-review-1440x900');
  await special.setViewportSize({width:960,height:540}); await special.waitForTimeout(300);
  await shot(special,'09-specialization-review-960x540');
  await click(special,'purchase_cancel'); await until(special,s=>s.mode==='workshop','specialization cancel');
  assert.equal((await state(special)).wallet,900); await special.context().close();
  assert.deepEqual(errors,[]);
  console.log('PURCHASE_REVIEW_WEB_PASS: actual browser input/rendering, Guest save failure, account transport mocks, desktop/small-screen captures');
  console.log('CAPTURES',shots);
} catch(error) {
  for(const page of pages) if(!page.isClosed()) await shot(page,'failure-'+page.label).catch(()=>{});
  throw error;
} finally { await browser.close(); await app.close(); }
