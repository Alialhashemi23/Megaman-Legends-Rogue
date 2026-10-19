// Read-only public deployment checks; fresh signed-out browser. No account use.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import WebSocket from '../server/node_modules/ws/wrapper.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const base=process.env.LIVE_URL||'https://megaman.galosengen.dev';
const out=path.join(root,'save','live36');fs.mkdirSync(out,{recursive:true});
const health=await fetch(base+'/healthz');assert.equal(health.status,200);
const payload=await fetch(base+'/index.pck');assert.equal(payload.status,200);
const sha=buffer=>crypto.createHash('sha256').update(buffer).digest('hex');
const actual=sha(Buffer.from(await payload.arrayBuffer()));
assert.equal(actual,sha(fs.readFileSync(path.join(root,'build/web/index.pck'))));
await new Promise((resolve,reject)=>{
 const socket=new WebSocket(base.replace(/^http/,'ws')+'/ws');
 const timer=setTimeout(()=>{socket.terminate();reject(new Error('WSS timeout'));},10000);
 socket.on('open',()=>socket.send(JSON.stringify({t:'hello',id:'ship36-check',name:'Build check',v:13,features:['ready_v1']})));
 socket.on('message',data=>{const message=JSON.parse(data);if(message.t==='welcome'){try{assert(message.features.includes('ready_v1'));clearTimeout(timer);socket.close();resolve();}catch(e){reject(e);}}});
 socket.on('error',reject);
});
console.log('LIVE36_HTTP_WSS_PASS: health 200; exact PCK SHA256 '+actual+'; WSS ready_v1');
const {chromium}=await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE).href);
const browser=await chromium.launch({executablePath:process.env.E2E_BROWSER_EXECUTABLE,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 const context=await browser.newContext({viewport:{width:1280,height:800}});
 const page=await context.newPage(),errors=[];
 page.on('console',m=>{if(/SCRIPT ERROR|Parse Error|Invalid access/.test(m.text()))errors.push(m.text());});
 await page.goto(base);await page.locator('#loader').waitFor({state:'hidden',timeout:90000});await page.waitForTimeout(1000);
 await page.screenshot({path:path.join(out,'title.png')});
 await page.keyboard.press('Enter');await page.waitForTimeout(500);
 await page.screenshot({path:path.join(out,'solo.png')});
 await page.keyboard.press('Escape');await page.waitForTimeout(500);
 await page.screenshot({path:path.join(out,'back.png')});
 assert.deepEqual(errors,[]);
 console.log('LIVE36_ANONYMOUS_BROWSER_PASS: fresh title/Solo/Back, captures, no script errors or account mutations');
} finally {await browser.close();}
