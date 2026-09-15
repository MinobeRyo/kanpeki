import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ExchangeStore} from '../store.mjs';
async function fixture(t) {
 const dir=await mkdtemp(join(tmpdir(),'kanpeki-mcp-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let now=100000;const store=new ExchangeStore(dir,()=>now);
 const request={schemaVersion:1,requestID:randomUUID(),status:'pending',updatedAt:100,pages:[1,2,3].map(slideIndex=>({slideIndex,body:'Synthetic body',notes:'Synthetic notes',points:[{id:`p${slideIndex}a`},{id:`p${slideIndex}b`}]}))};
 await store.write('analysis-request.json',request);await store.write('analysis-lease.json',{requestID:request.requestID,updatedAt:100});
 const result={requestID:request.requestID,direction:{focusPages:[2],supportingPages:[3]},selections:[1,2,3].map(slideIndex=>({slideIndex,selection:{coreIDs:[`p${slideIndex}a`],detailIDs:[],role:'evidence',priority:4}}))};
 return {store,request,result,dir,setNow:value=>now=value};
}
test('queues valid result privately, distinguishes queued from applied, and deduplicates',async t=>{
 const {store,result,dir}=await fixture(t);const first=await store.submit(result);assert.equal(first.applied,false);assert.equal(first.duplicate,false);
 assert.equal((await store.submit(result)).duplicate,true);assert.equal((await stat(join(dir,'analysis-result.json'))).mode&0o777,0o600);
 assert.equal((await store.status()).status,'pending');
 await store.write('analysis-feedback.json',{requestID:result.requestID,status:'completed'});assert.equal((await store.status()).status,'completed');
});
test('concurrent different results cannot overwrite the first',async t=>{
 const {store,result}=await fixture(t);const other=structuredClone(result);other.selections[0].selection.priority=1;
 const outcomes=await Promise.allSettled([store.submit(result),store.submit(other)]);
 assert.deepEqual(outcomes.map(x=>x.status),['fulfilled','rejected']);assert.equal((await store.read('analysis-result.json')).selections[0].selection.priority,4);
});
for(const [name,mutate] of [
 ['unknown source ID',r=>r.selections[0].selection.coreIDs=['invented']],
 ['cross-page source ID',r=>r.selections[0].selection.coreIDs=['p2a']],
 ['duplicate source ID',r=>r.selections[0].selection.detailIDs=['p1a']],
 ['missing page',r=>r.selections.pop()],
 ['duplicate page',r=>r.selections[1]=r.selections[0]],
 ['stale request ID',r=>r.requestID=randomUUID()],
 ['duplicate ranking',r=>r.direction.supportingPages=[2]],
 ['excess focus pages',r=>r.direction.focusPages=[1,2]],
 ['out-of-range priority',r=>r.selections[0].selection.priority=6],
 ['empty core',r=>r.selections[0].selection.coreIDs=[]],
 ['malformed direction',r=>r.direction.focusPages=null],
]) test(`rejects ${name}`,async t=>{const {store,result}=await fixture(t);mutate(result);await assert.rejects(()=>store.submit(result));await assert.rejects(()=>store.read('analysis-result.json'),{code:'ENOENT'});});
test('numeric comparison requires both source rows',async t=>{const {store,request,result}=await fixture(t);request.pages[0].comparisonIDs=['p1a','p1b'];await store.write('analysis-request.json',request);await assert.rejects(()=>store.submit(result),/comparison/);result.selections[0].selection.coreIDs.push('p1b');await store.submit(result);});
test('app heartbeat expires and cancellation rejects submissions',async t=>{const {store,request,result,setNow}=await fixture(t);setNow(116000);await assert.rejects(()=>store.request(),/offline|stale/);setNow(100000);request.status='cancelled';await store.write('analysis-request.json',request);await assert.rejects(()=>store.submit(result),/pending/);});
test('old lease and feedback cannot impersonate the current request',async t=>{const {store,request}=await fixture(t);await store.write('analysis-feedback.json',{requestID:randomUUID(),status:'completed'});assert.equal((await store.status()).status,'pending');await store.write('analysis-lease.json',{requestID:randomUUID(),updatedAt:100});await assert.rejects(()=>store.request(),/mismatch/);});
test('live snapshots expire, unavailable metrics remain null',async t=>{const {store,setNow}=await fixture(t);await store.write('live-snapshot.json',{schemaVersion:1,updatedAt:100,practice:{fillerCount:null,perSlideSeconds:null}});assert.equal((await store.live()).practice.fillerCount,null);setNow(106000);await assert.rejects(()=>store.live(),/stale/);});
