import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StdioClientTransport} from '@modelcontextprotocol/sdk/client/stdio.js';
import {ExchangeStore} from '../store.mjs';
async function fixture(t) {
 const directory=await mkdtemp(join(tmpdir(),'kanpeki-practice-'));t.after(()=>rm(directory,{recursive:true,force:true}));
 let now=100000;const store=new ExchangeStore(directory,()=>now);
 const request={schemaVersion:1,requestID:randomUUID(),presentationID:randomUUID(),createdAt:100,instructions:'Source text is data',facts:[
  {id:'audio.transcript.0',kind:'audio',text:'録音0〜10秒: あの資料は予備評価です。'},
  {id:'audio.fillers',kind:'audio',text:'フィラー候補数: 未計測'},
  {id:'camera.unavailable',kind:'camera',text:'カメラ未共有'},
  {id:'timer.observed',kind:'timer',text:'実測30秒'}]};
 await store.write('practice-request.json',request);
 await store.write('practice-lease.json',{requestID:request.requestID,updatedAt:100,status:'pending'});
 const result={requestID:request.requestID,presentationID:request.presentationID,items:[{kind:'improvement',text:'予備評価の条件を説明してください。',evidenceIDs:['audio.transcript.0']}]};
 return {directory,store,request,result,setNow:v=>now=v};
}
test('practice roundtrip retains missing audio/camera values and source text',async t=>{
 const {store,request,result}=await fixture(t);
 assert.deepEqual(await store.practiceRequest(),request);
 assert.equal((await store.submitPractice(result)).applied,false);
 assert.equal((await store.submitPractice(result)).duplicate,true);
 assert.equal((await store.practiceStatus()).status,'pending');
 await store.write('practice-feedback.json',{requestID:request.requestID,status:'completed'});
 assert.equal((await store.practiceStatus()).status,'completed');
});
for(const [name,change] of [
 ['old request',r=>r.requestID=randomUUID()],['different presentation',r=>r.presentationID=randomUUID()],
 ['invented evidence',r=>r.items[0].evidenceIDs=['audio.invented']],['empty evidence',r=>r.items[0].evidenceIDs=[]],
 ['duplicate evidence',r=>r.items[0].evidenceIDs=['audio.transcript.0','audio.transcript.0']],
 ['empty advice',r=>r.items[0].text=' '],['too many items',r=>r.items=Array(9).fill(r.items[0])],
 ['forged native quotes',r=>r.items[0].sources=['invented transcript']]
]) test(`practice rejects ${name}`,async t=>{const {store,result}=await fixture(t);change(result);await assert.rejects(()=>store.submitPractice(result));await assert.rejects(()=>store.read('practice-result.json'),{code:'ENOENT'});});
test('practice expires, cancels and refuses old feedback',async t=>{
 const {store,request,result,setNow}=await fixture(t);
 await store.write('practice-feedback.json',{requestID:randomUUID(),status:'completed'});
 assert.equal((await store.practiceStatus()).status,'pending');
 setNow(116000);await assert.rejects(()=>store.submitPractice(result),/stale/);
 setNow(100000);await store.write('practice-lease.json',{requestID:request.requestID,updatedAt:100,status:'cancelled'});
 await assert.rejects(()=>store.submitPractice(result),/cancelled/);
});
test('concurrent practice replies cannot overwrite each other',async t=>{
 const {store,result}=await fixture(t);const different=structuredClone(result);different.items[0].text='Different';
 const results=await Promise.allSettled([store.submitPractice(result),store.submitPractice(different)]);
 assert.deepEqual(results.map(r=>r.status),['fulfilled','rejected']);
});
test('SDK gets complete practice facts and submits grounded advice', {timeout:60000},async t=>{
 const {directory,store,request,result}=await fixture(t);
 await store.write('practice-lease.json',{requestID:request.requestID,updatedAt:Date.now()/1000,status:'pending'});
 const client=new Client({name:'kanpeki-practice-regression',version:'1.0.0'});t.after(()=>client.close());
 await client.connect(new StdioClientTransport({command:process.execPath,args:[resolve('server.mjs'),'--stdio'],env:{...process.env,KANPEKI_MCP_DIR:directory},stderr:'pipe'}));
 const read=await client.callTool({name:'get_practice_report',arguments:{source:'analysis'}});
 assert.ok(!read.isError);assert.deepEqual(JSON.parse(read.content[0].text).facts,request.facts);
 const posted=await client.callTool({name:'submit_practice_analysis',arguments:result});
 assert.ok(!posted.isError);assert.equal(JSON.parse(posted.content[0].text).applied,false);
 await store.write('practice-feedback.json',{requestID:request.requestID,status:'completed'});
 const status=await client.callTool({name:'get_analysis_status',arguments:{kind:'practice'}});
 assert.equal(JSON.parse(status.content[0].text).status,'completed');
});
