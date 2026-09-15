const {test}=require('node:test');
const assert=require('node:assert/strict');
const {Engine,csv,columns}=require('../Sources/KanpekiCamera/Resources/analysis.js');
const face=(yaw=0,pitch=0,x=0.2,size=0.5)=>({yaw,pitch,bbox:{x,y:0.1,width:size,height:size}});
const crowd=(count,pitch=0)=>Array.from({length:count},(_,i)=>face(0,pitch,i*0.08,0.06));
function run(engine,from,to,faces,step=500,extra={}){
  const rows=[];for(let t=from;t<=to+0.001;t+=step)rows.push(...engine.process({t,faces:typeof faces==='function'?faces(t):faces,...extra}).rows);return rows;
}
function presenter(testBuild=true){const e=new Engine({testBuild});e.setRole('audienceSide',0);e.centers={audience:{yaw:0,pitch:0},notes:{yaw:0,pitch:-30},screen:{yaw:40,pitch:0}};return e;}
test('A1: normalized pitch/yaw boundary and fractions',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 const rows=run(e,0,1000,[face(0,-16),face(21,0),face(0,-15),face(20,0)]);
 const s=rows.find(r=>r.type==='sample');assert.equal(s.faceCount,4);assert.equal(s.downRate,.25);assert.equal(s.attention,.5);
});
test('No detections are unknown attention, not perfect attention',()=>{
 const e=new Engine({mode:'audience'});const s=run(e,0,1000,[]).find(r=>r.type==='sample');assert.equal(s.faceCount,0);assert.equal(s.attention,null);assert.equal(s.downRate,null);
});
test('Unsupported angles remain missing and never count as forward',()=>{
 const e=new Engine({mode:'audience'});const s=run(e,0,1000,[face(null,null)]).find(r=>r.type==='sample');assert.equal(s.faceCount,1);assert.equal(s.attention,null);
});
test('A2: full and half down cues are detected within 10 seconds, no extra events',()=>{
 const e=new Engine({mode:'audience',testBuild:true});e.setRole('speakerSide',0);
 const rows=run(e,0,600000,t=>{
   let fs=crowd(t>=510000?7:10);
   if(t>=180000&&t<240000)fs=fs.map(f=>({...f,pitch:-30}));
   if(t>=330000&&t<420000)fs=fs.map((f,i)=>({...f,pitch:i<5?-30:0}));
   return fs;
 });
 const events=rows.filter(r=>r.event==='attentionDrop');assert.equal(events.length,2);
 [180000,330000].forEach((cue,i)=>assert.ok(Math.abs(events[i].elapsedMs-cue)<=10000));
 assert.equal(rows.find(r=>r.type==='sample'&&r.elapsedMs===420000).downRate,0);
 assert.equal(rows.find(r=>r.type==='sample'&&r.elapsedMs===510000).faceCount,7);
});
test('A2: zero false attention drops in a steady ten minute scene',()=>{
 const e=new Engine({mode:'audience'});assert.equal(run(e,0,600000,crowd(10)).filter(r=>r.event==='attentionDrop').length,0);
});
test('A3: independent synchronized nods are not removed as common camera motion',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 const rows=run(e,0,1000,t=>crowd(10,t===500?-8:0));assert.equal(rows.find(r=>r.type==='sample').nod,10);
});
test('A3: camera motion suppresses nods and clears partially observed cycles',()=>{
 const e=new Engine({mode:'audience'});const rows=run(e,0,1000,t=>crowd(10,t===500?-8:0),500,{cameraMoving:true});
 assert.equal(rows.find(r=>r.type==='sample').nod,0);
});
test('A3: stable and sub-threshold movements never nod',()=>{
 const e=new Engine({mode:'audience'});assert.ok(run(e,0,300000,t=>crowd(10,t%1000===500?-3:0)).filter(r=>r.type==='sample').every(r=>r.nod===0));
});
test('A3: crossing/new faces cannot reuse a remote face nod history',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 e.process({t:0,faces:[face(0,0,0,.08)]});e.process({t:500,faces:[face(0,-8,0,.08)]});
 assert.equal(e.process({t:1000,faces:[face(0,0,.8,.08)]}).latest.nod,0);
});
test('A4: switches within five seconds, keeps manual override',()=>{
 const e=new Engine({mode:'presenter'});let rows=run(e,0,5000,crowd(10));
 assert.equal(e.role,'speakerSide');assert.ok(rows.find(r=>r.event==='cameraRoleChanged').elapsedMs<=5000);
 run(e,5500,10500,[face()]);assert.equal(e.role,'audienceSide');
 e.setRole('speakerSide',11000);run(e,11000,30000,[face()]);assert.equal(e.role,'speakerSide');
 e.setRole(null,30500);run(e,30500,36000,[face()]);assert.equal(e.role,'audienceSide');
});
test('A4: two small audience faces and presenter with background face',()=>{
 const e=new Engine();run(e,0,5000,crowd(2));assert.equal(e.role,'speakerSide');
 run(e,5500,11000,[face(),face(0,0,.8,.06)]);assert.equal(e.role,'audienceSide');
});
test('A4: alternating boundary frames do not oscillate',()=>{
 const e=new Engine();const rows=run(e,0,60000,t=>t%1000===0?crowd(2):[face()]);assert.equal(rows.filter(r=>r.event==='cameraRoleChanged').length,0);
});
test('B1: real three second calibration, nearest direction and warning',()=>{
 const e=new Engine();e.setRole('audienceSide',0);
 e.beginCalibration('audience',0);run(e,0,2500,[face()]);assert.equal(e.centers.audience,undefined);
 e.process({t:3000,faces:[face()]});assert.deepEqual(e.centers.audience,{yaw:0,pitch:0});
 e.beginCalibration('notes',3500);run(e,3500,6500,[face(0,-30)]);
 e.beginCalibration('screen',7000);run(e,7000,10000,[face(40,0)]);assert.equal(e.warning,'');
 assert.equal(e.process({t:10500,faces:[face(1,-28)]}).gaze,'notes');
 assert.equal(e.process({t:11000,faces:[face(-70,40)]}).gaze,'away');
 e.beginCalibration('screen',11500);run(e,11500,14500,[face(0,-20)]);assert.match(e.warning,/区別不能/);
 assert.equal(e.gaze,null);
});
test('B1: calibration rejects missing, multiple faces and sparse sampling',()=>{
 for(const fs of [[],[face(),face()]]){const e=new Engine();e.beginCalibration('audience',0);run(e,0,3000,fs);assert.equal(e.centers.audience,undefined);assert.match(e.warning,/中断/);}
 const e=new Engine();e.beginCalibration('audience',0);e.process({t:0,faces:[face()]});e.process({t:3000,faces:[face()]});assert.equal(e.centers.audience,undefined);
});
test('Recalibration invalidates previous target immediately',()=>{
 const e=presenter();e.beginCalibration('notes',0);e.process({t:0,faces:[]});assert.equal(e.centers.notes,undefined);assert.equal(e.gaze,null);
});
test('B1: three ten-second notes visits trigger exactly three longNotes',()=>{
 const e=presenter();const rows=run(e,0,60000,t=>[face(0,((t>=5000&&t<15000)||(t>=25000&&t<35000)||(t>=45000&&t<55000))?-30:0)]);
 const notes=rows.filter(r=>r.event==='longNotes');assert.equal(notes.length,3);assert.ok(notes.every(r=>r.durationMs===8000));
 const shift=rows.find(r=>r.event==='gazeShift');assert.deepEqual([shift.from,shift.to,shift.durationMs],['audience','notes',5000]);
});
test('B1: notes less than eight seconds never trigger',()=>{
 const e=presenter();assert.equal(run(e,0,7000,[face(0,-30)]).filter(r=>r.event==='longNotes').length,0);
});
test('B1: face loss interrupts longNotes, reacquisition starts a new interval',()=>{
 const e=presenter();let rows=run(e,0,7000,[face(0,-30)]);rows.push(...run(e,7500,9000,[]));rows.push(...run(e,9500,16500,[face(0,-30)]));
 assert.equal(rows.filter(r=>r.event==='longNotes').length,0);rows.push(...run(e,17000,17500,[face(0,-30)]));assert.equal(rows.filter(r=>r.event==='longNotes').length,1);
});
test('B1: five second rates and 500ms gaze channel',()=>{
 const e=presenter();const rows=run(e,0,5000,t=>[face(0,t<=2500?0:-30)]);
 const sample=rows.find(r=>r.type==='sample'&&r.elapsedMs===5000);assert.equal(sample.audienceRate,.5);assert.equal(sample.notesRate,.5);
 assert.equal(rows.filter(r=>r.type==='gaze').length,11);
});
test('B2: head motion in degrees/sec and ranking >=2x',()=>{
 const values=[1,3,9].map(speed=>{const e=presenter();const rows=run(e,0,5000,t=>[face(t/1000*speed,0)]);return rows.filter(r=>r.type==='sample').map(r=>r.headMotion)[2];});
 assert.deepEqual(values,[1,3,9]);assert.ok(values[1]>=2*values[0]&&values[2]>=2*values[1]);
});
test('B3: inFrame zero during absence, no motion from re-entry',()=>{
 const e=presenter();run(e,0,1000,[face()]);const rows=run(e,1500,11000,[]);assert.ok(rows.filter(r=>r.type==='sample').every(r=>r.inFrame===0 && r.headMotion===null));
 const result=e.process({t:11500,faces:[face(70,0)]});assert.equal(result.latest.headMotion,null);
});
test('Clock gaps cannot produce a longNotes event from unobserved time',()=>{
 const e=presenter();run(e,0,1000,[face(0,-30)]);assert.equal(e.process({t:100000,faces:[face(0,-30)]}).rows.filter(r=>r.event==='longNotes').length,0);
});
test('Diagnostics measure frames at two and six fps, unknown battery stays blank',()=>{
 for(const fps of [2,6]){const e=new Engine({testBuild:true});const rows=run(e,0,20000,[],1000/fps,{batteryPercent:-100});
 const d=rows.filter(r=>r.type==='diagnostic');assert.equal(d.length,2);assert.ok(Math.abs(d[1].fps-fps)<.2);assert.equal(d[0].batteryPercent,null);}
});
test('Missing camera heartbeat does not inflate actual fps',()=>{
 const e=new Engine({testBuild:true});const rows=run(e,0,10000,[],500,{missing:true});assert.equal(rows.find(r=>r.type==='diagnostic').fps,0);
});
test('Production persistence excludes debug, telemetry, cue and observer rows',()=>{
 const e=presenter(false);e.cue(0,'test');e.observer(0,1,1,10,'observer');
 const rows=run(e,0,10000,[face(0,-30)]);assert.ok(rows.every(r=>['sample','gaze','event'].includes(r.type)));
 const serialized=JSON.stringify(rows);for(const forbidden of ['bbox','yaw','pitch','landmarks','image','batteryPercent','thermalState'])assert.ok(!serialized.includes(forbidden));
 assert.ok(rows.every(r=>Object.keys(r).every(k=>columns.includes(k))));
});
test('CSV escapes commas, quotes, linebreaks and spreadsheet formula cues',()=>{
 const e=new Engine({testBuild:true});e.cue(0,'=HYPERLINK("x,y")\nnext');const s=csv(e.drain());assert.ok(s.includes('"\'=HYPERLINK(""x,y"")\nnext"'));assert.ok(s.startsWith(columns.join(',')));
});
test('Observer input validation and scalar recording',()=>{
 const e=new Engine({testBuild:true});assert.throws(()=>e.observer(0,11,0,10,'a'));e.observer(0,4,3,10,'a');const row=e.drain()[0];assert.equal(row.downRate,.4);assert.equal(row.nod,3);
});
test('Invalid and out of order frame timestamps fail explicitly',()=>{
 const e=new Engine();e.process({t:0,faces:[]});for(const t of [0,-1,NaN,Infinity])assert.throws(()=>e.process({t,faces:[]}));
});
test('One hour simulation bounds temporal memory and drains output',()=>{
 const e=presenter();run(e,0,3600000,[face()]);assert.ok(e.gazeHistory.length<=10);assert.ok(e.frameTimes.length<=20);assert.ok(e.motion.length<=2);assert.equal(e.pending.length,0);
});
test('Identical input gives identical PC and iPhone channels and events',()=>{
 const pc=presenter(),ip=presenter();pc.meta.device='PC';ip.meta.device='iPhone';pc.epoch=ip.epoch=0;
 const input=t=>[face(0,t>=5000?-30:0)];const strip=rs=>rs.map(({device,...rest})=>rest);
 assert.deepEqual(strip(run(pc,0,20000,input)),strip(run(ip,0,20000,input)));
});
test('MediaPipe adapter uses column-major rotation and negative down pitch',()=>{
 const {matrixPose}=require('../Sources/KanpekiCamera/Resources/analysis.js');
 const a=Math.PI/6,c=Math.cos(a),s=Math.sin(a);
 const down=matrixPose([1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1]);assert.ok(Math.abs(down.pitch+30)<1e-9);
 const right=matrixPose([c,0,s,0,0,1,0,0,-s,0,c,0,0,0,0,1]);assert.ok(Math.abs(right.yaw-30)<1e-9);
 assert.deepEqual(matrixPose(null),{yaw:null,pitch:null});
});
test('Uncalibrated rates are unknown, not zero',()=>{
 const e=new Engine();e.setRole('audienceSide',0);const rows=run(e,0,1000,[face()]);const s=rows.find(r=>r.type==='sample');assert.equal(s.audienceRate,null);assert.equal(s.notesRate,null);
});
test('A different presenter cannot continue another person longNotes',()=>{
 const e=presenter();run(e,0,7000,[face(0,-30,0,.2)]);const rows=run(e,7500,10000,[face(0,-30,.8,.2)]);assert.equal(rows.filter(r=>r.event==='longNotes').length,0);
});
test('Small 2fps clock jitter does not halve channel cadence',()=>{
 const e=presenter();const rows=run(e,0,4990,[face()],499);
 assert.equal(rows.filter(r=>r.type==='gaze').length,11);
 assert.equal(rows.filter(r=>r.type==='sample').length,5);
});
test('A nod after an arbitrary long steady baseline is detected',()=>{
 const e=new Engine({mode:'audience'});e.setRole('speakerSide',0);
 const rows=run(e,0,4000,t=>crowd(10,t===2500?-8:0));
 assert.equal(rows.filter(r=>r.type==='sample').reduce((n,r)=>n+r.nod,0),10);
});
