const {test}=require('node:test'),assert=require('node:assert/strict');
const {Engine}=require('../Sources/KanpekiCamera/Resources/analysis.js');
// Synthetic 25 fps face with landmark geometry: nose 160 px below the top of a 640×480 frame,
// interocular 40 px. noseOffset(t) is added to the nose position (positive = head down).
function face(offset,yaw=0){
  return {bbox:{x:.3,y:.2,width:.25,height:.35},yaw,pitch:0,
    landmarks:{eyeY:150,eyeX:320,noseY:160+offset,noseX:320,chinY:200+offset,interocular:40,eyeNose:10,eyeChin:50,boxTopY:96,boxHeight:168}};
}
function nods(profile,options){
  const e=new Engine({mode:'audience',...options});e.setRole('speakerSide',0);let count=0;
  for(let i=0;i<profile.length;i++){const f=profile[i];const r=e.process({t:i*40,faces:f?[f]:[]});count+=r.rows.filter(x=>x.type==='sample').reduce((s,x)=>s+x.nod,0);}
  const last=e.process({t:profile.length*40+1000,faces:[]});return count+last.rows.filter(x=>x.type==='sample').reduce((s,x)=>s+x.nod,0);
}
const hold=n=>Array.from({length:n},()=>face(0));
// One quick nod: 8 px (20 % of interocular) down over 200 ms and back over 200 ms.
const quickNod=[...hold(30),...[2,4,6,8,8,6,4,2,0].map(v=>face(v)),...hold(30)];
test('A quick landmark nod is counted once and timed at its turning point',()=>{
  assert.equal(nods(quickNod),1);
  const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);let at=null;
  quickNod.forEach((f,i)=>{e.process({t:i*40,faces:[f]});for(const p of e.tracks)if(p.lastNod===i*40)at=p.nodAt;});
  assert.ok(at>=30*40&&at<=35*40,`turning point ${at}`);
});
test('A slow three-second lean and return is not a nod',()=>{
  const lean=[...hold(10),...Array.from({length:75},(_,i)=>face(i*8/75)),...Array.from({length:75},(_,i)=>face(8-i*8/75)),...hold(10)];
  assert.equal(nods(lean),0);
});
test('A vertical movement while the head turns sideways is not a nod',()=>{
  const turn=[...hold(30),...[2,4,6,8,8,6,4,2,0].map((v,i)=>face(v,i*10)),...hold(30)];
  assert.equal(nods(turn),0);
});
test('Movement below the landmark amplitude is ignored, and camera motion clears the cycle',()=>{
  // 1.5 px on a 40 px interocular distance is 3.75 %, below the 6 % proposal amplitude.
  const small=[...hold(30),...[.5,1,1.5,1.5,1,.5,0].map(v=>face(v)),...hold(30)];
  assert.equal(nods(small),0);
  const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);let count=0;
  quickNod.forEach((f,i)=>{const r=e.process({t:i*40,faces:[f],cameraMoving:i>=32&&i<=36});count+=r.rows.filter(x=>x.type==='sample').reduce((s,x)=>s+x.nod,0);});
  assert.equal(count,0);
});
test('Switching between landmark and pitch-only frames never reuses a stale baseline',()=>{
  const mixed=[...hold(20),...Array.from({length:10},()=>({bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:0})),...hold(20)];
  assert.equal(nods(mixed),0);
  const pitchOnly=[...Array.from({length:10},()=>({bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:0})),...hold(5),
    ...Array.from({length:10},(_,i)=>({bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:i<5?-8:0}))];
  assert.equal(nods(pitchOnly),0);
});
test('Thresholds for the landmark path are configurable and pitch-only inputs keep the legacy amplitude',()=>{
  assert.equal(nods(quickNod,{thresholds:{nodLandmarkAmplitude:30}}),0);
  const legacy=[...Array.from({length:5},()=>({bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:0})),
    {bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:-8},...Array.from({length:10},()=>({bbox:{x:.3,y:.2,width:.25,height:.35},yaw:0,pitch:0}))];
  const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);let count=0;
  legacy.forEach((f,i)=>{const r=e.process({t:i*500,faces:[f]});count+=r.rows.filter(x=>x.type==='sample').reduce((s,x)=>s+x.nod,0);});
  assert.equal(count,1);
});
