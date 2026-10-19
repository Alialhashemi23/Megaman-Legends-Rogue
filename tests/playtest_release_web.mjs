// Ordinary exported game, real browser, fresh profile, local disposable relay.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createServer} from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save','playtest-browser');fs.mkdirSync(out,{recursive:true});
const {chromium}=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const app=createServer({port:0,webRoot:path.join(root,'build/web'),log:()=>{}});const port=await app.listen();
const browser=await chromium.launch({headless:false,executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
const watchdog=setTimeout(()=>{console.error('PT12_BROWSER_TIMEOUT');process.exit(1);},60000);
try {
 const context=await browser.newContext({viewport:{width:1280,height:800}});
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
 assert.deepEqual(errors,[]);
 console.log('PT12_REAL_BROWSER_PASS: Options input enters/exits fullscreen; browser exit resyncs toggle; production Web export');
} finally {clearTimeout(watchdog);await browser.close();await app.close();}
