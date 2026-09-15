const {test}=require('node:test'),assert=require('node:assert/strict');
const {Engine}=require('../Sources/KanpekiCamera/Resources/analysis.js');
const face=yaw=>({yaw,pitch:0,bbox:{x:.2,y:.2,width:.3,height:.3}});
function engine(){const e=new Engine();e.setRole('audienceSide',0);e.centers={audience:{yaw:0,pitch:0},notes:{yaw:30,pitch:0},screen:{yaw:0,pitch:-40}};return e;}
test('Small pose noise at a direction boundary does not manufacture repeated gaze shifts',()=>{
 const e=engine();e.process({t:0,faces:[face(0)]});const shifts=[];
 for(let i=1;i<=10;i++)shifts.push(...e.process({t:i*500,faces:[face(i%2?15.5:14.5)]}).rows.filter(r=>r.event==='gazeShift'));
 assert.equal(shifts.length,0);
 const r=e.process({t:5500,faces:[face(25)]});assert.equal(r.gaze,'notes');
 assert.equal(r.rows.filter(r=>r.event==='gazeShift').length,1);
});
test('Hysteresis does not retain a previous direction after face loss',()=>{
 const e=engine();e.process({t:0,faces:[face(0)]});e.process({t:166,faces:[]});
 assert.equal(e.process({t:500,faces:[face(15.5)]}).gaze,'notes');
});
test('Looking beyond every calibrated direction still becomes away immediately',()=>{
 const e=engine();e.process({t:0,faces:[face(30)]});
 assert.equal(e.process({t:500,faces:[face(80)]}).gaze,'away');
});
