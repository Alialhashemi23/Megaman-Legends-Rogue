import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createServer } from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save','ui04-browser'); fs.mkdirSync(out,{recursive:true});
const { chromium }=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app=createServer({port:0,webRoot:path.join(root,'build/ui04-web'),log:()=>{}}); const port=await app.listen();
const browser=await chromium.launch({executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
let captures=0,verified=0;
try {
 for(const viewport of [{width:960,height:600},{width:1280,height:720},{width:1920,height:1080}].filter(v=>!process.env.UI04_WIDTH || v.width===Number(process.env.UI04_WIDTH))) {
  const context=await browser.newContext({viewport}); const page=await context.newPage(),errors=[]; page.setDefaultTimeout(30000);
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
  await page.goto(`http://127.0.0.1:${port}`,{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.ui04State,{timeout:90000});
  async function command(op,value,extra={}){await page.evaluate(r=>window.ui04Command(JSON.stringify(r)),{op,value,...extra});await page.waitForTimeout(500);}
  async function snap(label){await page.screenshot({path:path.join(out,`${viewport.width}x${viewport.height}-${label}.png`)});captures++;}
  async function state(){return page.evaluate(()=>window.ui04State);}
  async function screen(value){await command('screen',value);await page.waitForFunction(s=>window.ui04State.mode===s,value);assert((await state()).buttons.every(h=>h.valid),`${value} actions inside layout`);}
  await command('preset',false);await screen('title');await snap('standard-title');
  await command('preset',true);
  for(const mode of ['title','solo_prep','options','controls','account','lobby','workshop']){
   await screen(mode);await snap(`handheld-${mode}`);
   if(mode==='options')assert.equal((await state()).buttons.length,18);
   if(mode==='lobby')for(const action of ['ready','start_online','leave_online','lobby_workshop'])assert((await state()).buttons.some(b=>b.action===action),action);
  }
  for(const view of ['create','two_factor']){await command('auth',view);await snap(`handheld-account-${view}`);}
  await screen('workshop');
  await command('review');await page.waitForFunction(()=>window.ui04State.mode==='purchase_review');
  assert.equal((await state()).focus,'purchase_cancel');await snap('handheld-purchase');
  await page.keyboard.press('Escape');await page.waitForTimeout(1000);await page.waitForFunction(()=>window.ui04State.mode==='workshop' && window.ui04State.focus==='grid_node');
  assert.equal((await state()).focus,'grid_node');
  await screen('play');await snap('handheld-map-standard-camera');
  await command('screen','play',{close:true});await snap('handheld-map-close-camera');
  await command('lock');await snap('handheld-close-lockon');
  await screen('choice');await snap('handheld-choice');
  for(const kind of ['level','milestone']){await command('choice_kind',kind);await snap(`handheld-choice-${kind}`);}
  await page.keyboard.press('Escape');await page.waitForFunction(()=>window.ui04State.mode==='play');
  await screen('options');
  // Real mouse/controller-menu equivalents toggle the independently stored choices.
  const toggle=(await state()).buttons.find(b=>b.action==='option'&&b.value===14);
  await page.mouse.click(toggle.x*viewport.width,toggle.y*viewport.height);
  await page.waitForFunction(()=>!window.ui04State.handheld);
  await page.keyboard.press('ArrowRight');await page.waitForFunction(()=>window.ui04State.handheld);
  assert.equal((await page.evaluate(()=>JSON.parse(localStorage.getItem('relicDiverReadabilityV1')))).handheld_ui,true);await page.reload({waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>window.ui04State,{timeout:90000});
  assert.equal((await state()).handheld,true,'Handheld settings persist through actual browser reload');
  assert.equal((await state()).large_map,true,'Independent minimap preference persists');
  assert.deepEqual(errors,[]);verified++;console.log(`Verified ${viewport.width}x${viewport.height}`);await context.close();
 }
 console.log(`HANDHELD_WEB_PASS: ${captures} captures; ${verified} resolutions, title/prep/options/account/4-player lobby/Workshop/purchase/choice, Back focus, independent map/camera, lock-on, real mouse/key toggle and browser reload`);
} finally {await browser.close();await app.close();}
