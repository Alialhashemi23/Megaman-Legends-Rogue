import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {WebSocket} from 'ws';
import {createServer} from '../server.js';

test('Android metadata, immutable downloads and minimum online build', async () => {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'relic-android-'));
  const app=createServer({port:0,webRoot:dir,androidReleaseDir:dir,log:()=>{}});
  const port=await app.listen(), base='http://127.0.0.1:'+port;
  try {
    assert.equal((await fetch(base+'/updates/android/stable.json')).status,404);
    const m={versionCode:10,versionName:'0.18.0',gameProtocol:7,minimumOnlineVersionCode:2,downloadUrl:'/downloads/android/',bytes:4,sha256:'a'.repeat(64),signingFingerprint:'b'.repeat(64),notes:'<script>unsafe</script>'};
    fs.writeFileSync(path.join(dir,'stable.json'),JSON.stringify(m));
    fs.writeFileSync(path.join(dir,'relic-diver-10.apk'),'test');
    let r=await fetch(base+'/updates/android/stable.json');
    assert.deepEqual(await r.json(),m); assert.equal(r.headers.get('cache-control'),'no-store');
    r=await fetch(base+'/downloads/android/');
    const html=await r.text(); assert.ok(html.includes('&lt;script&gt;')); assert.ok(!html.includes('<script>')); assert.ok(html.includes(m.sha256)); assert.ok(html.includes('relic-diver-10.apk'));
    r=await fetch(base+'/downloads/android/relic-diver-10.apk');
    assert.equal(await r.text(),'test'); assert.ok(r.headers.get('cache-control').includes('immutable'));
    assert.equal((await fetch(base+'/downloads/android/stable.json')).status,404);
    assert.equal((await fetch(base+'/updates/android/stable.json',{method:'POST'})).status,405);
    async function hello(extra) {
      const ws=new WebSocket('ws://127.0.0.1:'+port+'/ws');
      try {return await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(new Error('WS timeout')),3000);
        ws.once('error',reject);
        ws.once('open',()=>ws.send(JSON.stringify({t:'hello',name:'Test',id:'test',v:7,...extra})));
        ws.once('message',data=>{clearTimeout(timer);resolve(JSON.parse(data));});
      });} finally {ws.close();}
    }
    assert.equal((await hello({platform:'android',androidVersionCode:1})).code,'update_required');
    assert.equal((await hello({platform:'android',androidVersionCode:2})).t,'welcome');
    assert.equal((await hello({platform:'android',androidVersionCode:2,v:6})).code,'update_required');
    assert.equal((await hello({})).t,'welcome');
    fs.writeFileSync(path.join(dir,'stable.json'),JSON.stringify({...m,minimumOnlineVersionCode:20}));
    assert.equal((await fetch(base+'/updates/android/stable.json')).status,404);
  } finally {await app.close();fs.rmSync(dir,{recursive:true,force:true});}
});
