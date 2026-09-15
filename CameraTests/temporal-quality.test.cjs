const {test}=require('node:test'),assert=require('node:assert/strict');
const {Engine}=require('../Sources/KanpekiCamera/Resources/analysis.js');
const face=(pitch=0,yaw=0)=>({pitch,yaw,bbox:{x:.2,y:.2,width:.3,height:.3}});
function nodEvents(series){const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);let count=0;
 for(const [t,pitch,yaw=0] of series){e.process({t,faces:[face(pitch,yaw)]});count+=e.tracks.filter(p=>p.lastNod===t).length;}return count;}
test('An old raised-head position cannot turn a later subthreshold dip into a nod',()=>{
 assert.equal(nodEvents([[0,4],[500,0],[1000,0],[1500,0],[2000,-2],[2500,4]]),0);
});
test('A brief horizontal turn and return is not a vertical nod',()=>{
 assert.equal(nodEvents([[0,0,0],[500,-8,40],[1000,0,0]]),0);
});
test('A gentle one-and-a-half-second vertical nod remains detectable',()=>{
 assert.equal(nodEvents(Array.from({length:19},(_,i)=>[i*1000/6,i<4?0:i<9?-(i-3)*2:i<14?-(13-i)*2:0])),1);
});
test('One dropped 6fps pose in the middle does not discard a steady three-second calibration',()=>{
 const e=new Engine();e.beginCalibration('notes',0);
 for(let i=0;i<=18;i++)e.process({t:i*1000/6,faces:i===7?[]:[face(-30)]});
 assert.deepEqual(e.centers.notes,{yaw:0,pitch:-30});assert.equal(e.warning,'');
});
test('A prolonged calibration dropout cannot be accepted from a few remaining samples',()=>{
 const e=new Engine();e.beginCalibration('notes',0);
 for(let i=0;i<=18;i++)e.process({t:i*1000/6,faces:i>=4&&i<=10?[]:[face(-30)]});
 assert.equal(e.centers.notes,undefined);assert.match(e.warning,/中断/);
});
test('Frequent short misses cannot manufacture sufficient calibration coverage',()=>{
 const e=new Engine();e.beginCalibration('notes',0);
 for(let i=0;i<=18;i++)e.process({t:i*1000/6,faces:[3,6,9,12].includes(i)?[]:[face(-30)]});
 assert.equal(e.centers.notes,undefined);assert.match(e.warning,/フレーム不足/);
});
test('Changing camera role cancels a pending presenter calibration',()=>{
 const e=new Engine();e.beginCalibration('notes',0);
 for(let t=0;t<=1000;t+=500)e.process({t,faces:[face(-30)]});
 e.setRole('speakerSide',1100);
 for(let t=1500;t<=3500;t+=500)e.process({t,faces:[face(-30)]});
 assert.equal(e.centers.notes,undefined);assert.equal(e.calibration,null);assert.match(e.warning,/役割/);
});
