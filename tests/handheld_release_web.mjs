import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createServer } from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save','ui04-release-browser');fs.mkdirSync(out,{recursive:true});
const profile={version:4,revision:0,kills:0,runs:0,wins:0,deepest:0,discovered:{},best_time:0,zenny:500,trees:{},legacy_unlocks:[]};
const body=JSON.stringify(profile),code='RD2.'+Buffer.from(body).toString('base64')+'.'+crypto.createHash('sha256').update(body).digest('hex');
const { chromium }=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app=createServer({port:0,webRoot:path.join(root,'build/web'),log:()=>{}});const port=await app.listen();
const browser=await chromium.launch({executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
try {
 const context=await browser.newContext({viewport:{width:960,height:600}});
 await context.addInitScript(value=>{if(!localStorage.getItem('relicDiverProgressV2'))localStorage.setItem('relicDiverProgressV2',value);},code);
 const page=await context.newPage(),errors=[];page.setDefaultTimeout(30000);
 page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
 const saved=()=>page.evaluate(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])));
 async function loaded(){await page.locator('#loader').waitFor({state:'hidden',timeout:90000});await page.waitForTimeout(1200);}
 await page.goto(`http://127.0.0.1:${port}`,{waitUntil:'domcontentloaded'});await loaded();
 assert.equal(await page.evaluate(()=>typeof window.ui04Command),'undefined','Fixture excluded');
 for(let i=0;i<3;i++)await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter');await page.waitForTimeout(400);
 for(let i=0;i<14;i++)await page.keyboard.press('ArrowDown');
 await page.keyboard.press('ArrowRight');await page.keyboard.press('ArrowDown');await page.keyboard.press('ArrowRight');await page.keyboard.press('ArrowDown');await page.keyboard.press('ArrowRight');
 await page.waitForTimeout(500);await page.screenshot({path:path.join(out,'01-options-device-preferences.png')});
 await page.keyboard.press('Escape');
 assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('relicDiverReadabilityV1'))),{handheld_ui:true,large_minimap:true,close_camera:true});
 await page.reload({waitUntil:'domcontentloaded'});await loaded();
 await page.screenshot({path:path.join(out,'02-reloaded-handheld-title.png')});
 // Clicking the taller handheld Workshop row after reload proves the reflow and
 // its hit geometry persisted, then uses the ordinary purchase flow.
 await page.mouse.click(314/1440*960,487/900*600);await page.waitForTimeout(400);
 await page.keyboard.press('Enter');await page.waitForTimeout(400);
 await page.screenshot({path:path.join(out,'03-handheld-review.png')});
 assert.equal((await saved()).zenny,500);
 await page.keyboard.press('ArrowRight');await page.keyboard.down('Enter');await page.waitForTimeout(500);await page.keyboard.up('Enter');
 await page.waitForFunction(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])).zenny===400);
 assert.deepEqual((await saved()).trees['0'],['frame']);await page.screenshot({path:path.join(out,'04-handheld-confirmed.png')});
 assert.deepEqual(errors,[]);
 console.log('HANDHELD_RELEASE_WEB_PASS: ordinary production export, no hooks, keyboard Options, device preferences persisted across reload, reflowed mouse hit targets, fresh/held Confirm spends once');
} finally {await browser.close();await app.close();}
