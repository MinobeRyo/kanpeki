const {test}=require('node:test');
const assert=require('node:assert/strict');
const {Engine}=require('../Sources/KanpekiCamera/Resources/analysis.js');
const face=(pitch=0,x=.2)=>({yaw:0,pitch,bbox:{x,y:.2,width:.2,height:.2}});
test('Calibration cannot combine two people at different positions',()=>{
 const e=new Engine();e.beginCalibration('notes',0);
 for(let t=0;t<=3000;t+=500)e.process({t,faces:[face(-30,t<1500?.1:.65)]});
 assert.equal(e.centers.notes,undefined);assert.match(e.warning,/中断/);
});
test('One bad pose cannot shift an otherwise steady calibration center',()=>{
 const e=new Engine();e.beginCalibration('audience',0);
 for(let t=0;t<=3000;t+=500)e.process({t,faces:[face(t===1500?70:0)]});
 assert.ok(e.centers.audience);assert.ok(Math.abs(e.centers.audience.pitch)<1);
});
test('Unstable calibration is rejected instead of averaging two directions',()=>{
 const e=new Engine();e.beginCalibration('audience',0);
 for(let t=0;t<=3000;t+=500)e.process({t,faces:[face(t<1500?-30:0)]});
 assert.equal(e.centers.audience,undefined);assert.match(e.warning,/中断/);
});
test('Face loss between gaze output ticks breaks longNotes continuity',()=>{
 const e=new Engine();e.setRole('audienceSide',0);
 e.centers={audience:{yaw:0,pitch:0},notes:{yaw:0,pitch:-30},screen:{yaw:40,pitch:0}};
 let events=[];
 for(let i=0;i<=54;i++)events.push(...e.process({t:i*1000/6,faces:i===43?[]:[face(-30)]}).rows);
 assert.equal(events.filter(r=>r.event==='longNotes').length,0);
});
