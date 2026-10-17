import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../scripts/controller_probe.gd',import.meta.url),'utf8');
const encoded=source.match(/JavaScriptBridge\.eval\("(.+)", true\)/)[1];
const code=JSON.parse('"'+encoded+'"');
function sample(navigator){return JSON.parse(vm.runInNewContext(code,{navigator}));}
assert.deepEqual(sample({}),[]);
assert.deepEqual(sample(undefined),[]);
const pad={index:2,id:'Unknown Steam test',mapping:'',connected:true,axes:[0.1,-0.4,0,1],buttons:[{value:0},{value:0.7}]};
assert.deepEqual(sample({getGamepads:()=>[null,{...pad,connected:false},pad]}),[{index:2,id:pad.id,mapping:'',axes:pad.axes,buttons:[0,0.7]}]);
assert.equal(sample({getGamepads:()=>[{...pad,mapping:'standard'}]})[0].mapping,'standard');
assert.deepEqual(sample({getGamepads:()=>{throw Error('blocked');}}),[]);
console.log('CONTROLLER_BROWSER_PROBE_PASS: actual bridge expression, standard/non-standard/absent/blocked API and analog buttons');
