// Four serial real two-client sessions. No accounts or production services.
import fs from 'node:fs';
import path from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import {createServer} from '../server/server.js';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'save',`pt08-${Date.now()}`);fs.mkdirSync(out,{recursive:true});
for(const scenario of ['win','loss','down','guest_leave']) {
 const folder=path.join(out,scenario);fs.mkdirSync(folder,{recursive:true});
 const app=createServer({port:0,log:()=>{},readiness:{countdownMs:200}});const port=await app.listen();
 const children=[];let timer;
 try {
  const results=await Promise.race([
   Promise.all([1,2].map(index=>new Promise((resolve,reject)=>{
    const runtime=path.join(folder,`runtime-${index}`);fs.mkdirSync(runtime,{recursive:true});
    const child=spawn(process.env.GODOT,['--headless','--path',root,'--script','tests/playtest_lobby_driver.gd','--',`--server=ws://127.0.0.1:${port}/ws`,`--player-id=pt08-${scenario}-${index}`,`--index=${index}`,`--scenario=${scenario}`,`--folder=${folder}`],{cwd:root,windowsHide:true,env:{...process.env,APPDATA:runtime,LOCALAPPDATA:runtime},stdio:['ignore','pipe','pipe']});
    children.push(child);let log='';
    const record=data=>{log+=data;fs.appendFileSync(path.join(folder,`p${index}.log`),data);};
    child.stdout.on('data',record);child.stderr.on('data',record);child.on('error',reject);
    child.on('exit',code=>{
     const match=log.match(/PT08_PASS (.+)/);
     if(code!==0||!match||/SCRIPT ERROR|PT08_FAIL/.test(log))reject(new Error(`${scenario} P${index} exit ${code}\n${log}`));
     else resolve(JSON.parse(match[1]));
    });
   }))),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(`${scenario} timeout`)),45000);})
  ]);
  assert.equal(new Set(results.map(r=>r.code)).size,1,'same room code through results and restart');
  assert(results[0].restarted);assert(results[1].restarted||results[1].left);
  console.log('PT08_REAL_CLIENTS_PASS',scenario,JSON.stringify(results));
 } finally {
  clearTimeout(timer);
  for(const child of children)if(child.exitCode===null)spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'],{windowsHide:true,stdio:'ignore'});
  await app.close();
 }
}
console.log('PT08_COMPLETE',out);
