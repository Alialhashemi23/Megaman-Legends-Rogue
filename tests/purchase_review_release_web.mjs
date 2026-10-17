// Ordinary production Web export, no fixture scene/hooks. A fresh browser gets
// only synthetic Guest progress through the existing save-code mirror.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createServer } from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save','ui03-ordinary-browser'); fs.mkdirSync(out,{recursive:true});
const profile={version:4,revision:0,kills:0,runs:0,wins:0,deepest:0,discovered:{},best_time:0,zenny:500,trees:{},legacy_unlocks:[]};
const body=JSON.stringify(profile);
const code='RD2.'+Buffer.from(body).toString('base64')+'.'+crypto.createHash('sha256').update(body).digest('hex');
const { chromium }=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app=createServer({port:0,webRoot:path.join(root,'build/web'),log:()=>{}}); const port=await app.listen();
const browser=await chromium.launch({executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--autoplay-policy=no-user-gesture-required']});
const context=await browser.newContext({viewport:{width:960,height:600}});
await context.addInitScript(value=>{if(!localStorage.getItem('relicDiverProgressV2'))localStorage.setItem('relicDiverProgressV2',value);},code);
const page=await context.newPage(),errors=[];
page.on('pageerror',e=>errors.push(e.message));
page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
const saved=()=>page.evaluate(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])));
async function loaded(){await page.locator('#loader').waitFor({state:'hidden',timeout:90000});await page.waitForTimeout(1200);}
async function workshop(){await page.keyboard.press('ArrowDown');await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter');await page.waitForTimeout(400);}
try {
 await page.goto(`http://127.0.0.1:${port}`,{waitUntil:'domcontentloaded'});await loaded();
 assert.equal(await page.evaluate(()=>typeof window.ui03Command),'undefined','Production export excludes fixture hooks');
 await workshop();await page.keyboard.press('Enter');await page.waitForTimeout(350);
 await page.screenshot({path:path.join(out,'01-production-guest-review.png')});
 await page.keyboard.press('Enter');await page.waitForTimeout(300);
 assert.equal((await saved()).zenny,500,'Default Cancel spends nothing');
 await page.keyboard.press('Enter');await page.waitForTimeout(350);await page.keyboard.press('ArrowRight');
 await page.keyboard.down('Enter');
 await page.waitForFunction(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])).zenny===400,null,{timeout:15000});
 await page.keyboard.down('Enter');await page.waitForTimeout(350);await page.keyboard.up('Enter');
 let confirmed=await saved();assert.equal(confirmed.zenny,400);assert.deepEqual(confirmed.trees['0'],['frame']);
 await page.screenshot({path:path.join(out,'02-production-guest-confirmed.png')});
 await page.reload({waitUntil:'domcontentloaded'});await loaded();
 confirmed=await saved();assert.equal(confirmed.zenny,400);assert.deepEqual(confirmed.trees['0'],['frame']);
 await workshop();await page.keyboard.press('Enter');await page.waitForTimeout(350);
 await page.screenshot({path:path.join(out,'03-production-reloaded-next-circuit.png')});
 await page.keyboard.press('Escape');assert.equal((await saved()).zenny,400);
 assert.deepEqual(errors,[]);
 console.log('PURCHASE_RELEASE_WEB_PASS: ordinary export, no hooks, default Cancel, fresh/held Confirm, one Guest spend, reload and next-circuit review');
} catch(error) {await page.screenshot({path:path.join(out,'failure.png')}).catch(()=>{});throw error;}
finally {await browser.close();await app.close();}
