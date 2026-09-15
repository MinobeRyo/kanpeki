const {test}=require('node:test'),assert=require('node:assert/strict');
const {Engine}=require('../Sources/KanpekiCamera/Resources/analysis.js');
const face=(x,pitch=0,width=.2)=>({yaw:0,pitch,bbox:{x,y:.2,width,height:width}});
function identities(reverse){
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 e.process({t:0,faces:[face(.1),face(.24)]});
 const input=[face(.18),face(.25)];
 e.process({t:166,faces:reverse?input.reverse():input});
 return e.tracks.slice().sort((a,b)=>a.bbox.x-b.bbox.x).map(p=>p.id);
}
test('Nearby face association is independent of detector result order',()=>{
 assert.deepEqual(identities(false),[1,2]);assert.deepEqual(identities(true),[1,2]);
});
test('A face moving toward its neighbour does not inherit the neighbours downward pose',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 e.process({t:0,faces:[face(.1,0),face(.24,0)]});
 e.process({t:500,faces:[face(.1,0),face(.24,-12)]});
 e.process({t:1000,faces:[face(.18,0),face(.25,-12)]});
 assert.equal(e.tracks.filter(p=>p.lastNod===1000).length,0);
 assert.deepEqual(e.tracks.map(p=>p.id),[1,2]);
});
test('A sudden fourfold face size change cannot reuse the same person history',()=>{
 const e=new Engine();e.process({t:0,faces:[face(.2,0,.1)]});const first=e.tracks[0].id;
 const replacement=face(.05,-30,.4);replacement.bbox.y=.05;
 e.process({t:166,faces:[replacement]});assert.notEqual(e.tracks[0].id,first);
});
test('Thirty adjacent stationary faces keep their identities when result order reverses',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 const input=Array.from({length:30},(_,i)=>({yaw:0,pitch:0,bbox:{x:(i%10)*.095,y:Math.floor(i/10)*.25,width:.09,height:.18}}));
 e.process({t:0,faces:input});e.process({t:166,faces:input.slice().reverse()});
 assert.deepEqual(e.tracks.map(p=>p.id),Array.from({length:30},(_,i)=>30-i));
});
