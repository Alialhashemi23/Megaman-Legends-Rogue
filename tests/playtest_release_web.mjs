// Ordinary exported game, real browser, fresh profile, local disposable relay.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createServer} from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save','playtest-browser');fs.mkdirSync(out,{recursive:true});
const {chromium}=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app=createServer({port:0,webRoot:path.join(root,'build/web'),log:()=>{}});const port=await app.listen();
const browser=await chromium.launch({headless:false,executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const watchdog=setTimeout(()=>{console.error('PLAYTEST_BROWSER_TIMEOUT');process.exit(1);},90000);
try {
 const context=await browser.newContext({viewport:{width:1280,height:800}});
 const body=JSON.stringify({version:4,revision:0,kills:0,runs:0,wins:0,deepest:0,discovered:{},best_time:0,zenny:500,trees:{},legacy_unlocks:[]});
 const code='RD2.'+Buffer.from(body).toString('base64')+'.'+crypto.createHash('sha256').update(body).digest('hex');
 await context.addInitScript(value=>{if(!localStorage.getItem('relicDiverProgressV2'))localStorage.setItem('relicDiverProgressV2',value);},code);
 const page=await context.newPage(),errors=[];
 page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
 await page.goto(`http://127.0.0.1:${port}`);
 console.log('PT12 browser loading',port);
 await page.locator('#loader').waitFor({state:'hidden',timeout:90000});await page.waitForTimeout(1500);
 // Title -> Options. Fullscreen is Options row 5 (zero based).
 for(let i=0;i<3;i++)await page.keyboard.press('ArrowDown');
 await page.keyboard.press('Enter');await page.waitForTimeout(600);
 for(let i=0;i<5;i++)await page.keyboard.press('ArrowDown');
 await page.keyboard.press('Enter');
 console.log('PT12 fullscreen requested');
 await page.waitForFunction(()=>!!document.fullscreenElement,{timeout:10000});
 await page.screenshot({path:path.join(out,'fullscreen.png')});
 await page.keyboard.press('Enter');
 await page.waitForFunction(()=>!document.fullscreenElement,{timeout:10000});
 await page.screenshot({path:path.join(out,'windowed.png')});
 await page.keyboard.press('Enter');await page.waitForFunction(()=>!!document.fullscreenElement);
 await page.evaluate(()=>document.exitFullscreen());await page.waitForTimeout(500);
 await page.keyboard.press('Enter');await page.waitForFunction(()=>!!document.fullscreenElement);
 await page.evaluate(()=>document.exitFullscreen());
 await page.waitForTimeout(500);
 // Browsers may consume the first Esc after leaving fullscreen. Click the
 // visible Options Back button, which also returns keyboard focus to canvas.
 await page.mouse.click(930,695);await page.waitForTimeout(500);
 await page.keyboard.press('ArrowUp');await page.keyboard.press('Enter');await page.waitForTimeout(400);
 await page.keyboard.press('Enter');await page.waitForTimeout(400);
 const saved=()=>page.evaluate(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])));
 assert.equal((await saved()).zenny,500,'Selecting spends nothing');
 await page.screenshot({path:path.join(out,'workshop-selected.png')});
 await page.keyboard.down('Enter');await page.waitForTimeout(600);await page.keyboard.up('Enter');
 await page.waitForFunction(()=>JSON.parse(atob(localStorage.getItem('relicDiverProgressV2').split('.')[1])).zenny===400);
 assert.deepEqual((await saved()).trees['0'],['frame']);
 await page.screenshot({path:path.join(out,'workshop-purchased.png')});
 await page.reload();await page.locator('#loader').waitFor({state:'hidden',timeout:90000});await page.waitForTimeout(1000);
 assert.equal((await saved()).zenny,400,'Saved purchase survives reload');
 await page.keyboard.press('Enter');await page.waitForTimeout(400);
 await page.keyboard.press('Enter');await page.waitForTimeout(300);
 await page.keyboard.press('Escape');await page.waitForTimeout(300);
 await page.screenshot({path:path.join(out,'solo-back-to-carousel.png')});
 await page.keyboard.press('Escape');await page.waitForTimeout(300);
 await page.screenshot({path:path.join(out,'solo-back-to-title.png')});
 assert.deepEqual(errors,[]);
 console.log('PT12_REAL_BROWSER_PASS: Options input enters/exits fullscreen; browser exit resyncs toggle; production Web export');
 console.log('PLAYTEST_RELEASE_BROWSER_PASS: inline selection, fresh/held purchase once, persisted reload, Solo Back captures; no fixture hooks');
} finally {clearTimeout(watchdog);await browser.close();await app.close();}
