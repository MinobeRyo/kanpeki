import { readFile, stat, writeFile, rename, mkdir } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
export const roles = ['title','problem','overview','solution','mechanism','evidence','limitation','conclusion','supporting','future','value','closing'];
const MAX_BYTES = 8 * 1024 * 1024;
export class ExchangeStore {
  constructor(directory, now = () => Date.now()) { this.directory = directory; this.now = now; this.submissions = Promise.resolve(); }
  async read(name) {
    const path = join(this.directory, name);
    const info = await stat(path);
    if (!info.isFile() || info.size > MAX_BYTES) throw Error('Snapshot exceeds size limit');
    const data = await readFile(path);
    if (data.length > MAX_BYTES) throw Error('Snapshot exceeds size limit');
    return JSON.parse(data.toString('utf8'));
  }
  async write(name, data) {
    await mkdir(this.directory, {recursive:true, mode:0o700});
    const temporary = join(this.directory, `${name}.${randomUUID()}.tmp`);
    await writeFile(temporary, JSON.stringify(data), {mode:0o600});
    await rename(temporary, join(this.directory, name));
  }
  async request() {
    const value = await this.read('analysis-request.json');
    if (value.schemaVersion !== 1 || value.status !== 'pending' || !Array.isArray(value.pages) || !value.pages.length) throw Error('No pending analysis request');
    const lease = await this.read('analysis-lease.json');
    if (lease.requestID !== value.requestID) throw Error('Analysis lease mismatch');
    value.updatedAt = lease.updatedAt;
    if (!Number.isFinite(value.updatedAt) || this.now()/1000-value.updatedAt > 15 || value.updatedAt-this.now()/1000 > 5) throw Error('Analysis app is offline or request is stale');
    return value;
  }
  async live() {
    const value = await this.read('live-snapshot.json');
    if (value.schemaVersion !== 1 || !Number.isFinite(value.updatedAt) || this.now()/1000-value.updatedAt > 5 || value.updatedAt-this.now()/1000 > 5) throw Error('Mac snapshot is stale or sharing is stopped');
    return value;
  }
  async status() {
    const request = await this.read('analysis-request.json');
    try {
      const feedback = await this.read('analysis-feedback.json');
      if (feedback.requestID === request.requestID) return feedback;
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    const current = await this.request();
    return {requestID:current.requestID, status:'pending', message:'Native app has not applied a result for this request'};
  }
  submit(result) {
    const next = this.submissions.then(() => this.submitOnce(result));
    this.submissions = next.catch(() => {});
    return next;
  }
  async submitOnce(result) {
    const request = await this.request();
    validateResult(request, result);
    const digest = createHash('sha256').update(JSON.stringify(result)).digest('hex');
    try {
      const existing = await this.read('analysis-result.json');
      if (existing.requestID === request.requestID) {
        if (existing.digest !== digest) throw Error('A different result was already submitted for this request');
        return {accepted:true,applied:false,requestID:request.requestID,duplicate:true};
      }
    } catch(error) { if (error.code !== 'ENOENT') throw error; }
    // Native client independently rechecks the request ID and all source IDs before applying.
    if ((await this.request()).requestID !== request.requestID) throw Error('Request changed during submission');
    await this.write('analysis-result.json', {...result,digest,submittedAt:this.now()/1000});
    return {accepted:true,applied:false,requestID:request.requestID,duplicate:false};
  }
}
export function validateResult(request, result) {
  if (result.requestID !== request.requestID) throw Error('Request ID changed. Fetch the current request again.');
  const count = request.pages.length, d=result.direction;
  if (!d || !Array.isArray(d.focusPages) || !Array.isArray(d.supportingPages) || !d.focusPages.length || d.focusPages.length>Math.max(1,Math.floor(count/3)) || d.supportingPages.length>Math.max(1,Math.floor(count/2))) throw Error('Invalid global page ranking');
  const ranking=[...d.focusPages,...d.supportingPages];
  if (new Set(ranking).size!==ranking.length || ranking.some(i=>!Number.isInteger(i)||i<1||i>count)) throw Error('Duplicate or invalid ranked page');
  if (!Array.isArray(result.selections)||result.selections.length!==count||new Set(result.selections.map(p=>p.slideIndex)).size!==count) throw Error('Submit exactly one selection for every page');
  for(const page of result.selections) {
    const source=request.pages.find(p=>p.slideIndex===page.slideIndex), s=page.selection;
    if(!source||!s||!roles.includes(s.role)||!Number.isInteger(s.priority)||s.priority<1||s.priority>5||!Array.isArray(s.coreIDs)||!s.coreIDs.length||s.coreIDs.length>32||!Array.isArray(s.detailIDs)||s.detailIDs.length>32) throw Error('Invalid page selection');
    const ids=[...s.coreIDs,...s.detailIDs], valid=new Set(source.points.map(p=>p.id));
    if(new Set(ids).size!==ids.length||ids.some(id=>!valid.has(id))) throw Error(`Unknown or duplicate source ID on page ${page.slideIndex}`);
    if(source.comparisonIDs?.length && s.coreIDs.filter(id=>source.comparisonIDs.includes(id)).length<2) throw Error(`Keep two comparison rows on page ${page.slideIndex}`);
  }
}
