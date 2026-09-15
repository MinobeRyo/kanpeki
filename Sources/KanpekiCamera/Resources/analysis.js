/* Shared by JavaScriptCore (Vision) and PC (MediaPipe). No storage or network APIs.
 * Input angles: degrees, looking down is negative pitch, subject's right positive yaw.
 * bbox is normalized top-left coordinates, used in memory only for temporal tracking.
 */
(function (root) {
  'use strict';
  const targets = ['audience', 'notes', 'screen'];
  const defaults = Object.freeze({ downPitch: -15, forwardYaw: 20, nodAmplitude: 5,
    nodMinMs: 250, nodMaxMs: 2000, nodCooldownMs: 800, nodBaselineMs: 1000, nodMaxYawChange: 30,
    // Landmark path (nose-tip vertical position in % of interocular distance) when faces carry landmarks.
    // Loose proposal stage (high recall) gated by the trained candidate classifier (nodClassifier).
    // Rule-only operation: nodClassifier:false with amplitude 10, maxMs 1000, landmark cooldown 800, recover 1
    nodLandmarkAmplitude: 6, nodLandmarkMaxMs: 1500, nodStrokeMs: 600, nodRecover: 0.6,
    nodMinVelocity: 0, nodSmoothMs: 80, nodScaleMs: 5000, nodLandmarkCooldownMs: 400,
    // Threshold 0.4 keeps the shipped detector's recall at 6 fps with far fewer false positives; 0.3 favours recall.
    nodClassifier: true, nodClassifierThreshold: 0.4, nodDecisionDelayMs: 600, nodHistoryMs: 2200,
    // Also propose "up then down" strokes (a mirrored detector on the inverted signal).
    nodBothDirections: false, roleWindowMs: 5000,
    roleVote: 0.8, largeFaceArea: 0.20, calibrationMs: 3000,
    calibrationSeparation: 15, awayDegrees: 35, gazeHysteresis: 3, dropDelta: 0.20,
    dropCooldownMs: 20000, longNotesMs: 8000, staleMs: 1100 });
  const columns = ['schemaVersion','sessionId','device','scenario','build','type','elapsedMs','utc',
    'cameraRole','faceCount','attention','downRate','nod','gazeTarget','audienceRate','notesRate',
    'headMotion','inFrame','fps','batteryPercent','thermalState','event','from','to','durationMs','value'];
  const mean = a => a.length ? a.reduce((s, v) => s + v, 0) / a.length : null;
  // Candidate classifier for landmark motion; provisional AMI-trained weights. NOD_MODEL_BEGIN
  const nodModel = {"features":["driftBefore","eyeP2p","flips","ioRange","maxVelocity","meanAbsVelocity","p2p","p2pCore","peak","peakPos","pitchMin","pitchP2p","rate","stdBefore","stdCore","vertVsHoriz","xRange","yawMean","yawRange"],"logFeatures":["eyeP2p","ioRange","maxVelocity","meanAbsVelocity","p2p","p2pCore","peak","pitchP2p","stdBefore","stdCore","vertVsHoriz","xRange","yawRange"],"bias":-1.688206,"weights":{"driftBefore":-0.002842,"eyeP2p":-0.613861,"flips":0.034713,"ioRange":-6.7595,"maxVelocity":-0.101477,"meanAbsVelocity":2.074692,"p2p":-1.406718,"p2pCore":1.553737,"peak":-0.456856,"peakPos":-0.713694,"pitchMin":0.018157,"pitchP2p":0.044211,"rate":-0.082189,"stdBefore":-0.146192,"stdCore":-0.481995,"vertVsHoriz":1.264491,"xRange":0.071055,"yawMean":-0.019602,"yawRange":0.354892}};
  // NOD_MODEL_END
  // Shape features of a nod candidate at turning point `at` (seconds) from per-track samples
  // {t, nose, eye, pitch, yaw, x, io} covering [at-1.5, at+0.6]. Uses no frame after at+0.6 s.
  function nodFeatures(samples, at) {
    const w=(from,to,key)=>samples.filter(s=>s.t>=at+from && s.t<=at+to && s[key]!==null && s[key]!==undefined).map(s=>s[key]);
    const avg=a=>a.length?a.reduce((x,y)=>x+y,0)/a.length:0;
    const std=a=>{const m=avg(a);return Math.sqrt(avg(a.map(v=>(v-m)**2)));};
    const nose=w(-0.6,0.6,'nose'), noseBefore=w(-1.5,-0.6,'nose'), core=w(-0.4,0.4,'nose');
    if(nose.length<6 || core.length<2)return null;
    const ts=samples.filter(s=>s.t>=at-0.6 && s.t<=at+0.6 && s.nose!==null && s.nose!==undefined).map(s=>s.t);
    const rate=(ts.length-1)/Math.max(1e-6,ts[ts.length-1]-ts[0]);
    const base=avg(w(-0.6,-0.3,'nose').concat(w(0.3,0.6,'nose')));
    const pitch=w(-0.6,0.6,'pitch'), yaw=w(-0.6,0.6,'yaw'), x=w(-0.6,0.6,'x'), eye=w(-0.6,0.6,'eye'), io=w(-0.6,0.6,'io');
    const sm=nose.map((v,i,a)=>avg(a.slice(Math.max(0,i-1),i+2)));
    const d=sm.slice(1).map((v,i)=>v-sm[i]);
    let flips=0;for(let i=1;i<d.length;i++)if(Math.sign(d[i])!==Math.sign(d[i-1]) && d[i]!==0)flips++;
    const peakIdx=core.indexOf(Math.max(...core));
    const range=a=>a.length?Math.max(...a)-Math.min(...a):0;
    // Mouth activity: chin-to-nose distance changes when talking or laughing but not when the whole head nods.
    const mouth=samples.filter(s=>s.t>=at-0.6 && s.t<=at+0.6 && Number.isFinite(s.chin) && s.nose!==null && s.nose!==undefined).map(s=>s.chin-s.nose);
    return {peak:Math.max(...core)-base, p2p:range(nose), p2pCore:range(core), eyeP2p:range(eye),
      mouthStd:mouth.length>=3?std(mouth):0, mouthRange:range(mouth), mouthVsNod:mouth.length>=3?std(mouth)/(0.5+std(core)):0,
      pitchP2p:range(pitch), pitchMin:pitch.length?Math.min(...pitch):0,
      yawRange:range(yaw), yawMean:yaw.length?Math.abs(avg(yaw)):0, xRange:range(x), ioRange:range(io),
      flips, stdBefore:std(noseBefore), stdCore:std(core),
      driftBefore:noseBefore.length?avg(core)-avg(noseBefore):0,
      maxVelocity:Math.max(...d.map(Math.abs))*rate, meanAbsVelocity:avg(d.map(Math.abs))*rate,
      peakPos:peakIdx/Math.max(1,core.length-1), vertVsHoriz:range(nose)/(0.01+range(x)), rate};
  }
  function nodScore(features, model) {
    if(!features || !model)return null;
    let z=model.bias;
    for(const name of model.features){
      const raw=features[name]; if(!Number.isFinite(raw))return null;
      const v=model.logFeatures.includes(name)?Math.log1p(Math.max(0,raw)):raw;
      z+=model.weights[name]*v;
    }
    return 1/(1+Math.exp(-z));
  }
  const median = a => {const s=a.slice().sort((x,y)=>x-y),m=Math.floor(s.length/2);return s.length%2?s[m]:(s[m-1]+s[m])/2;};
  const distance = (a,b) => Math.hypot(a.yaw-b.yaw, a.pitch-b.pitch);
  const finitePose = f => Number.isFinite(f.yaw) && Number.isFinite(f.pitch);
  // Joint one-to-one assignment prevents an early, ambiguous detection from
  // stealing its neighbour's track. Extra columns represent new people.
  function associateFaces(faces, old) {
    const n=faces.length, m=old.length+n;
    if(!n || !old.length)return faces.map(()=>null);
    const costs=faces.map(f=>old.map(p=>{
      const a=f.bbox,b=p.bbox;
      const size=Math.max(a.width/b.width,b.width/a.width,a.height/b.height,b.height/a.height);
      const d=Math.hypot(a.x+a.width/2-b.x-b.width/2,a.y+a.height/2-b.y-b.height/2);
      const gate=Math.max(.035,Math.min(a.width,b.width)*.6);
      return size<=2 && d<gate ? d/gate : 1e6;
    }).concat(Array(n).fill(1)));
    // Rectangular Hungarian assignment; all dummy costs are finite.
    const u=Array(n+1).fill(0),v=Array(m+1).fill(0),p=Array(m+1).fill(0),way=Array(m+1).fill(0);
    for(let i=1;i<=n;i++){
      p[0]=i;let j0=0;const min=Array(m+1).fill(Infinity),used=Array(m+1).fill(false);
      do{
        used[j0]=true;const i0=p[j0];let delta=Infinity,j1=0;
        for(let j=1;j<=m;j++)if(!used[j]){
          const cur=costs[i0-1][j-1]-u[i0]-v[j];
          if(cur<min[j]){min[j]=cur;way[j]=j0;}
          if(min[j]<delta){delta=min[j];j1=j;}
        }
        for(let j=0;j<=m;j++)if(used[j]){u[p[j]]+=delta;v[j]-=delta;}else min[j]-=delta;
        j0=j1;
      }while(p[j0]);
      do{const j1=way[j0];p[j0]=p[j1];j0=j1;}while(j0);
    }
    const result=faces.map(()=>null);
    for(let j=1;j<=old.length;j++)if(p[j] && costs[p[j]-1][j-1]<1)result[p[j]-1]=old[j-1];
    return result;
  }
  function csvCell(v) {
    if (v === null || v === undefined) return '';
    let s = String(v);
    if (/^[=+@\t\r]/.test(s) || /^-[^0-9.]/.test(s)) s = "'" + s;
    return '"' + s.replace(/"/g, '""') + '"';
  }
  function csv(rows) { return columns.join(',') + '\r\n' + rows.map(r => columns.map(k => csvCell(r[k])).join(',')).join('\r\n') + '\r\n'; }
  class Engine {
    constructor(options) {
      const o = options || {};
      this.config = Object.assign({}, defaults, o.thresholds || {});
      this.meta = {schemaVersion: 1, sessionId: o.sessionId || 'session', device: o.device || 'PC',
        scenario: o.scenario || 'B1', build: o.testBuild ? 'test' : 'production'};
      this.testBuild = !!o.testBuild;
      this.epoch = o.epochMs === undefined ? Date.now() : o.epochMs;
      this.role = o.mode === 'audience' ? 'speakerSide' : 'audienceSide';
      this.manualRole = null;
      this.roleVotes = [];
      this.centers = {};
      this.calibration = null;
      this.warning = '';
      this.tracks = [];
      this.nextID = 1;
      this.lastTime = -1;
      this.lastFrame = -Infinity;
      this.lastGazeTick = -Infinity;
      this.lastSample = 0;
      this.lastDiagnostic = 0;
      this.frameTimes = [];
      this.gaze = null;
      this.gazeStart = 0;
      this.longNotesSent = false;
      this.gazeHistory = [];
      this.motion = [];
      this.lastSpeaker = null;
      this.nods = new Set();
      this.downHistory = [];
      this.lastDrop = -Infinity;
      this.pending = [];
      this.latest = {};
    }
    row(type, t, fields) {
      const row = Object.assign({}, this.meta, {type, elapsedMs: Math.round(t),
        utc: new Date(this.epoch + t).toISOString(), cameraRole: this.role}, fields || {});
      // Only an explicit scalar allowlist can cross the persistence boundary.
      const clean = {};
      columns.forEach(k => { if (row[k] !== undefined && (row[k] === null || ['string','number','boolean'].includes(typeof row[k]))) clean[k] = row[k]; });
      this.pending.push(clean);
      return clean;
    }
    drain() { const rows = this.pending; this.pending = []; return rows; }
    event(name,t,fields) { this.row('event',t,Object.assign({event:name},fields)); }
    cue(t,label) { if (this.testBuild) this.row('cue',t,{value:String(label).slice(0,160)}); }
    observer(t,down,nods,total,observerID) {
      if (!this.testBuild) return;
      if (![down,nods,total].every(Number.isInteger) || total < 1 || down < 0 || nods < 0 || down > total || nods > total) throw Error('人数が不正です');
      this.row('observer',t,{downRate:down/total,faceCount:total,nod:nods,value:String(observerID).slice(0,40)});
    }
    setRole(role,t) {
      if (role !== null && !['speakerSide','audienceSide'].includes(role)) throw Error('Unknown role');
      this.manualRole = role; this.roleVotes = [];
      if (role) this.changeRole(role,t);
    }
    changeRole(role,t) {
      if (role === this.role) return;
      const old = this.role; this.role = role;
      if(this.calibration){
        this.calibration=null;this.warning='較正中断：カメラの役割が変わりました';
      }
      this.resetGaze(t); this.tracks = []; this.nods.clear(); this.downHistory = [];
      this.event('cameraRoleChanged',t,{from:old,to:role});
    }
    beginCalibration(target,t) {
      if (!targets.includes(target)) throw Error('Unknown calibration target');
      if (this.role !== 'audienceSide') throw Error('発表者カメラで較正してください');
      // Invalidate the previous center immediately so failed re-calibration cannot reuse it.
      delete this.centers[target];
      this.calibration = {target,started:t,samples:[]}; this.warning = '';
      this.resetGaze(t);
    }
    calibrate(faces,t) {
      const c = this.calibration;
      if (!c) return;
      if (faces.length !== 1 || !finitePose(faces[0])) {
        // Preserve an established, steady calibration through a brief detector miss.
        // Multiple faces, missing endpoints and sustained loss remain failures.
        if (faces.length<=1 && c.samples.length && t-c.started<this.config.calibrationMs &&
            t-c.lastValid<=400) {c.dropouts=(c.dropouts||0)+1;return;}
        this.warning = '較正中断：顔を1人だけ映してください'; this.calibration = null; return;
      }
      const last=c.samples[c.samples.length-1], current=faces[0];
      if (last && (Math.hypot(current.bbox.x+current.bbox.width/2-last.bbox.x-last.bbox.width/2,
          current.bbox.y+current.bbox.height/2-last.bbox.y-last.bbox.height/2) > Math.min(current.bbox.width,last.bbox.width)*0.6 ||
          current.bbox.width/last.bbox.width>2 || last.bbox.width/current.bbox.width>2)) {
        this.warning='較正中断：顔の位置が変わりました。同じ位置でやり直してください';this.calibration=null;return;
      }
      c.samples.push(faces[0]);
      c.lastValid=t;
      if (t-c.started < this.config.calibrationMs) return;
      if (c.samples.length < 6 || c.samples.length/(c.samples.length+(c.dropouts||0))<0.8) {
        this.warning = '較正中断：フレーム不足'; this.calibration = null; return;
      }
      const center={yaw:median(c.samples.map(f=>f.yaw)),pitch:median(c.samples.map(f=>f.pitch))};
      const stable=c.samples.filter(f=>distance(f,center)<=10);
      if(stable.length<6 || stable.length/c.samples.length<0.8){
        this.warning='較正中断：向きが安定していません。向き先を見続けてください';this.calibration=null;return;
      }
      this.centers[c.target] = {yaw:mean(stable.map(f=>f.yaw)),pitch:mean(stable.map(f=>f.pitch))};
      this.calibration = null;
      this.warning = '';
      for (let i=0;i<targets.length;i++) for (let j=i+1;j<targets.length;j++) {
        const a=this.centers[targets[i]], b=this.centers[targets[j]];
        if (a && b && distance(a,b)<this.config.calibrationSeparation) this.warning='区別不能：向き先の角度差を15°以上にしてください';
      }
      this.event('calibrationCompleted',t,{value:c.target});
      if (this.warning) this.event('calibrationWarning',t,{value:'indistinguishable'});
    }
    resetGaze(t) {
      this.gaze = null; this.gazeStart = t; this.longNotesSent = false;
      this.lastSpeaker = null; this.gazeHistory = []; this.motion = [];
    }
    updateRole(faces,t,dt) {
      if (this.manualRole || !faces.length) return;
      const largest = Math.max(...faces.map(f=>f.bbox.width*f.bbox.height));
      const vote = faces.length >= 3 || (faces.length===2 && largest<this.config.largeFaceArea) ? 'speakerSide' : 'audienceSide';
      this.roleVotes.push({t,dt:Math.min(dt,600),vote});
      this.roleVotes = this.roleVotes.filter(v=>v.t>t-this.config.roleWindowMs);
      const total=this.roleVotes.reduce((s,v)=>s+v.dt,0);
      const weight=this.roleVotes.filter(v=>v.vote===vote).reduce((s,v)=>s+v.dt,0);
      if (total>=this.config.roleWindowMs*0.8 && weight/total>=this.config.roleVote) this.changeRole(vote,t);
    }
    track(faces,t,moving) {
      const old=this.tracks.filter(x=>t-x.t<=this.config.staleMs);
      const matches=associateFaces(faces,old);
      this.tracks=faces.map((f,index)=> {
        const match=matches[index];
        const p=match || {id:this.nextID++,base:f.pitch,low:f.pitch,start:t,t,phase:'idle',lastNod:-Infinity};
        // Keep short physical nods observable. A three-sample median was rejected:
        // independent AMI annotations showed substantially worse event recall.
        const pitch=f.pitch;
        const maxYaw=this.config.nodMaxYawChange;
        const landmark=this.nodLandmark(f,p,t);
        if(landmark!==null){
          this.trackLandmarkNod(p,f,landmark,t,moving);
        } else if(moving || !finitePose(f) || !Number.isFinite(p.base)) {
          p.base=pitch;p.low=pitch;p.start=t;p.phase='idle';p.poseWindow=[];
        } else {
          p.poseWindow=(p.poseWindow||[]).filter(x=>t-x.t<=this.config.nodBaselineMs);
          if(p.phase==='down' && (t-p.start>this.config.nodMaxMs || Math.abs(f.yaw-p.nodYaw)>maxYaw)){
            p.phase='idle';p.poseWindow=[];
          }
          if(p.phase==='idle') {
            p.base=Math.max(pitch,...p.poseWindow.map(x=>x.pitch));
            if(p.base-pitch>=this.config.nodAmplitude){
              p.phase='down';p.start=p.t;p.low=pitch;p.nodYaw=Number.isFinite(p.yaw)?p.yaw:f.yaw;p.nodYawDelta=0;
            }
          }
          if(p.phase==='down'){
            p.nodYawDelta=Math.max(p.nodYawDelta,Math.abs(f.yaw-p.nodYaw));
            if(p.nodYawDelta>maxYaw){p.phase='idle';p.poseWindow=[];p.base=pitch;p.low=pitch;}
          }
          p.low=Math.min(p.low,pitch);
          const recovered=pitch-p.low;
          const required=this.config.nodAmplitude;
          if(p.phase==='down' && Math.abs(f.yaw-p.nodYaw)<=maxYaw && recovered>=required &&
              t-p.start>=this.config.nodMinMs && t-p.lastNod>=this.config.nodCooldownMs){
            this.nods.add(p.id);p.lastNod=t;p.base=pitch;p.low=pitch;p.start=t;p.phase='idle';p.poseWindow=[];
          }
          p.poseWindow.push({t,pitch});
        }
        return Object.assign(p,f,{t});
      });
      if (moving) this.nods.clear();
    }
    // Nose-tip vertical position in percent of a per-track median interocular distance; null without landmarks.
    // Down movement increases the value. The scale window is several seconds long so the scale cannot
    // follow the head tilt inside a nod and cancel the movement being measured.
    nodLandmark(f,p,t) {
      const l=f.landmarks;
      if(!l || !Number.isFinite(l.noseY) || !Number.isFinite(l.interocular) || l.interocular<=0)return null;
      p.scales=(p.scales||[]).filter(x=>t-x.t<=this.config.nodScaleMs).concat({t,v:l.interocular});
      return l.noseY/median(p.scales.map(x=>x.v))*100;
    }
    // Causal nod detector on the landmark signal: a down stroke of at least the amplitude within the
    // stroke time, then a recovery, with a minimum peak velocity so slow leaning is not a nod.
    // The event time is the turning point; the cooldown clock starts when the recovery is confirmed.
    trackLandmarkNod(p,f,value,t,moving) {
      const c=this.config, maxYaw=c.nodMaxYawChange;
      // Per-track sample history for the candidate classifier (scalars only, ~2 s, memory only).
      const l=f.landmarks, scale=median(p.scales.map(x=>x.v));
      p.history=(p.history||[]).filter(x=>t-x.t*1000<=c.nodHistoryMs);
      p.history.push({t:t/1000, nose:value, eye:l.eyeY/scale*100, x:l.noseX/scale*100, io:l.interocular/scale,
        chin:Number.isFinite(l.chinY)?l.chinY/scale*100:null,
        pitch:finitePose(f)?f.pitch:null, yaw:finitePose(f)?f.yaw:null});
      this.decidePendingNod(p,t);
      if(moving || !finitePose(f)){p.phase='idle';p.raw=[];p.poseWindow=[];p.base=NaN;p.pendingNods=[];return;}
      p.raw=(p.raw||[]).filter(x=>t-x.t<=c.nodSmoothMs).concat({t,v:value});
      const v=mean(p.raw.map(x=>x.v));
      // Entries from the pitch path carry no landmark value and must not seed this baseline.
      p.poseWindow=(p.poseWindow||[]).filter(x=>t-x.t<=c.nodBaselineMs && Number.isFinite(x.v));
      const ref=p.poseWindow.slice().reverse().find(x=>t-x.t>=100) || p.poseWindow[0];
      const velocity=ref && t>ref.t ? (v-ref.v)/((t-ref.t)/1000) : 0;
      let turning=this.landmarkStroke(p,p,v,t,f,velocity);
      if(c.nodBothDirections){
        // Mirrored detector: an "up then down" stroke on the inverted signal shares the same baseline window.
        p.mirror=p.mirror||{phase:'idle',poseWindow:[]};
        p.mirror.poseWindow=p.poseWindow.map(x=>({t:x.t,v:-x.v}));
        const up=this.landmarkStroke(p,p.mirror,-v,t,f,-velocity);
        if(up!==null && turning===null)turning=up;
      }
      if(turning!==null){
        p.poseWindow=[];p.raw=[];p.lastProposal=t;if(p.mirror)p.mirror.phase='idle';
        // lastNod marks confirmed events only; scorers and the benchmark read it as the event flag.
        if(c.nodClassifier && nodModel){(p.pendingNods=p.pendingNods||[]).push({at:turning});}
        else{this.nods.add(p.id);p.lastNod=t;p.nodAt=turning;}
      }
      // A later pitch-only frame must restart from its own baseline, never from this percent value.
      p.base=NaN;
      p.poseWindow.push({t,v});
    }
    // One stroke state machine on a signal where the movement of interest increases the value.
    // Returns the turning-point time when a down-and-back cycle completes, else null.
    landmarkStroke(p,s,v,t,f,velocity) {
      const c=this.config, maxYaw=c.nodMaxYawChange;
      if(s.phase==='down' && (t-s.start>c.nodLandmarkMaxMs || Math.abs(f.yaw-s.nodYaw)>maxYaw || s.lowT-s.start>c.nodStrokeMs)){
        // An abandoned cycle must not seed a new stroke from the same baseline on this frame.
        s.phase='idle';if(s===p){p.poseWindow=[];p.raw=[{t,v}];}else s.poseWindow=[];
      }
      if(s.phase!=='down'){
        // The stroke starts the last time the head was at its highest, so a still head does not age the start.
        const base=s.poseWindow.reduce((m,x)=>x.v<=m.v?x:m,s.poseWindow[0]||{t,v});
        // A track must have a full baseline window before it may propose; the first frames of a track
        // are still initialising the scale and smoothing and produce spurious strokes.
        const settled=p.history && p.history.length>1 && t/1000-p.history[0].t>=c.nodBaselineMs/1000;
        if(settled && v-base.v>=c.nodLandmarkAmplitude && t-base.t<=c.nodStrokeMs){
          s.phase='down';s.start=base.t;s.low=v;s.lowT=t;s.nodYaw=f.yaw;s.peakVelocity=velocity;
        }
        return null;
      }
      s.peakVelocity=Math.max(s.peakVelocity,velocity);
      if(v>s.low){s.low=v;s.lowT=t;}
      if(s.low-v>=c.nodRecover*c.nodLandmarkAmplitude && t-s.lowT<=c.nodStrokeMs &&
         s.peakVelocity>=c.nodMinVelocity && t-Math.max(p.lastNod,p.lastProposal||-Infinity)>=c.nodLandmarkCooldownMs){
        s.phase='idle';return s.lowT;
      }
      return null;
    }
    // A proposed nod is confirmed once nodDecisionDelayMs of history after its turning point exists
    // and the classifier score reaches the threshold. The event keeps the turning-point time.
    // Proposals are queued: nods in quick succession each get their own decision, in order.
    decidePendingNod(p,t) {
      const c=this.config;
      while(p.pendingNods && p.pendingNods.length && t-p.pendingNods[0].at>=c.nodDecisionDelayMs){
        const pending=p.pendingNods.shift(), at=pending.at/1000;
        const score=nodScore(nodFeatures(p.history.filter(s=>s.t>=at-1.5 && s.t<=at+0.6),at),nodModel);
        if(score!==null && score>=c.nodClassifierThreshold){this.nods.add(p.id);p.lastNod=t;p.nodAt=pending.at;p.nodScore=score;}
      }
    }
    presenter(faces,t) {
      // Largest face is the presenter; require continuity to avoid motion from person swaps.
      const f=faces.slice().sort((a,b)=>b.bbox.width*b.bbox.height-a.bbox.width*a.bbox.height)[0];
      const valid=f && finitePose(f);
      // Continuity must break immediately, even between the 500 ms output ticks.
      if (!valid) this.resetGaze(t);
      if (valid && this.lastSpeaker && this.lastSpeaker.id!==f.id) this.resetGaze(t);
      if (valid && this.lastSpeaker && t-this.lastSpeaker.t<=this.config.staleMs && this.lastSpeaker.id===f.id) {
        this.motion.push({t,amount:distance(f,this.lastSpeaker),dt:t-this.lastSpeaker.t});
      }
      this.lastSpeaker=valid?Object.assign({t},f):null;
      // Bucket against the session clock; small camera jitter must not halve 2fps output.
      if (Math.floor((t+20)/500)<=Math.floor((this.lastGazeTick+20)/500)) return;
      this.lastGazeTick=t;
      let gaze=null;
      if (valid && !this.calibration && !this.warning && targets.every(k=>this.centers[k])) {
        const sorted=targets.map(k=>({k,d:distance(f,this.centers[k])})).sort((a,b)=>a.d-b.d);
        gaze=sorted[0].d<=this.config.awayDegrees?sorted[0].k:'away';
        // A small pose fluctuation at a class boundary is not a new glance.
        // Keep a known direction only while it is still within the away limit.
        const previous=sorted.find(x=>x.k===this.gaze);
        if(gaze!=='away' && previous && previous.d<=this.config.awayDegrees &&
           previous.d-sorted[0].d<this.config.gazeHysteresis)gaze=previous.k;
      }
      if (gaze!==this.gaze) {
        if (gaze && this.gaze) this.event('gazeShift',t,{from:this.gaze,to:gaze,durationMs:Math.round(t-this.gazeStart)});
        this.gaze=gaze;this.gazeStart=t;this.longNotesSent=false;
      }
      if (gaze==='notes' && !this.longNotesSent && t-this.gazeStart>=this.config.longNotesMs) {
        this.event('longNotes',t,{durationMs:Math.round(t-this.gazeStart)});this.longNotesSent=true;
      }
      this.gazeHistory.push({t,gaze});
      this.gazeHistory=this.gazeHistory.filter(v=>v.t>t-5000);
      this.row('gaze',t,{gazeTarget:gaze});
    }
    process(frame) {
      const t=frame.t;
      if (!Number.isFinite(t) || t<0 || t<=this.lastTime) throw Error('Timestamps must increase');
      const dt=this.lastTime<0?0:t-this.lastTime;
      if (dt>this.config.staleMs) {this.resetGaze(t);this.tracks=[];this.nods.clear();this.roleVotes=[];this.downHistory=[];
        if(this.calibration){this.calibration=null;this.warning='較正中断：カメラ入力が途切れました';}}
      this.lastTime=t;
      const faces=(frame.faces || []).filter(f=>f.bbox && ['x','y','width','height'].every(k=>Number.isFinite(f.bbox[k])) && f.bbox.width>0 && f.bbox.height>0);
      if (!frame.missing) {this.lastFrame=t;this.frameTimes.push(t);}
      this.frameTimes=this.frameTimes.filter(x=>x>t-10000);
      this.updateRole(faces,t,dt);
      this.calibrate(faces,t);
      this.track(faces,t,!!frame.cameraMoving);
      if (this.role==='audienceSide') this.presenter(this.tracks,t);
      const poses=faces.filter(finitePose);
      const down=mean(poses.map(f=>f.pitch<this.config.downPitch?1:0));
      const attention=mean(poses.map(f=>f.pitch>=this.config.downPitch && Math.abs(f.yaw)<=this.config.forwardYaw?1:0));
      if (Math.floor((t+20)/1000)>Math.floor((this.lastSample+20)/1000)) {
        this.lastSample=t;
        this.motion=this.motion.filter(v=>v.t>t-1000);
        const duration=this.motion.reduce((s,v)=>s+v.dt,0);
        const gazeWindow=this.gazeHistory.filter(v=>v.t>t-5000);
        const speaker=this.role==='audienceSide';
        this.latest=this.row('sample',t,{faceCount:faces.length,attention:speaker?null:attention,downRate:speaker?null:down,
          nod:speaker?null:this.nods.size,gazeTarget:speaker?this.gaze:null,
          audienceRate:speaker && gazeWindow.some(v=>v.gaze)?mean(gazeWindow.map(v=>v.gaze==='audience'?1:0)):null,
          notesRate:speaker && gazeWindow.some(v=>v.gaze)?mean(gazeWindow.map(v=>v.gaze==='notes'?1:0)):null,
          headMotion:speaker && duration?this.motion.reduce((s,v)=>s+v.amount,0)/(duration/1000):null,
          inFrame:speaker?(faces.length?1:0):null});
        if (!speaker && down!==null) {
          this.downHistory.push({t,down}); this.downHistory=this.downHistory.filter(v=>v.t>t-25000);
          const recent=this.downHistory.filter(v=>v.t>t-5000), baseline=this.downHistory.filter(v=>v.t<=t-5000);
          if (recent.length>=4 && baseline.length>=10 && mean(recent.map(v=>v.down))-mean(baseline.map(v=>v.down))>=this.config.dropDelta && t-this.lastDrop>=this.config.dropCooldownMs) {
            this.event('attentionDrop',t,{value:'down'});this.lastDrop=t;
          }
        }
        this.nods.clear();
      }
      if (this.testBuild && Math.floor((t+20)/10000)>Math.floor((this.lastDiagnostic+20)/10000)) {
        this.lastDiagnostic=t;
        this.row('diagnostic',t,{fps:this.frameTimes.length/10,
          batteryPercent:Number.isFinite(frame.batteryPercent) && frame.batteryPercent>=0?frame.batteryPercent:null,
          thermalState:frame.thermalState || null});
      }
      return {rows:this.drain(),latest:this.latest,role:this.role,gaze:this.gaze,
        calibrated:targets.filter(k=>this.centers[k]),calibrating:this.calibration?this.calibration.target:null,warning:this.warning};
    }
  }
  function matrixPose(m) {
    if (!m || m.length!==16 || !Array.from(m).every(Number.isFinite)) return {yaw:null,pitch:null};
    return {yaw:Math.atan2(m[2],Math.hypot(m[0],m[1]))*180/Math.PI,
      pitch:-Math.atan2(m[6],m[10])*180/Math.PI};
  }
  root.AnalysisKit={Engine,defaults,columns,csv,matrixPose,nodFeatures,nodScore,nodModel};
  if (typeof module!=='undefined') module.exports=root.AnalysisKit;
})(globalThis);
