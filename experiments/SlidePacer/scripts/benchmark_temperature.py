"""Paired, sequential local temperature benchmark using extracted production Swift logic."""
from pathlib import Path
import argparse, json, re, subprocess, urllib.request, time, hashlib, random, datetime
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evaluation/temperature-comparison'
BUILD=ROOT/'.build/temperature-comparison'
TEMPS=[0.0,0.35,0.5,0.7,1.0]
DECKS={'wn':'wn','research':'発表スライド'}
def read(p): return json.loads(p.read_text())
def write(p,d): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,ensure_ascii=False,indent=2))
def compile_helper():
 s=(ROOT/'SlidePacer/ContentView.swift').read_text()
 models=s[s.index('@Generable(description: "1枚'):s.index('enum OllamaClient')]
 models=re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n','',models).replace('private ','')
 slide=s[s.index('struct SlideInput:'):s.index('// MARK: - PPTX')]
 instructions=s[s.index('let defaultInstructions ='):s.index('// MARK: - ContentView')]
 prompt=s[s.index('    private func buildPrompt('):s.index('    private func runAnalysis()')].replace('private func','func')
 h='import Foundation\n'+slide+models+instructions+'''
let mode=CommandLine.arguments[1]
let folder=URL(fileURLWithPath:CommandLine.arguments[2])
let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("slides.json"))) as! [[String:Any]]
let slides=raw.map {SlideInput(body:$0["body"] as! String,notes:$0["notes"] as! String)}
let theme=CommandLine.arguments[3]
let presentationGoal=""
let audience=""
let temperature=Double(CommandLine.arguments[4])!
let encoder=JSONEncoder()
encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
'''+prompt+'''
struct Record:Encodable {let slideIndex:Int;let roleHint:String?;let points:[SourcePoint];let request:OllamaGenerateRequest}
struct ReadRecord:Decodable {let slideIndex:Int;let roleHint:String?;let points:[SourcePoint]}
struct Saved:Decodable {let slideIndex:Int;let response:Response;struct Response:Decodable {let response:String;let done_reason:String?}}
do {
if mode=="prepare" {
 let prompt=DeckDirector.prompt(slides:slides,theme:theme,goal:presentationGoal,audience:audience,outlineLimit:16384*2/3)
 let request=DeckDirector.request(model:"qwen3.5:9b",prompt:prompt,count:slides.count,temperature:temperature,context:16384)
 try JSONSerialization.data(withJSONObject:request,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("direction-request.json"))
} else {
 let direction=try JSONDecoder().decode(DeckDirection.self,from:Data(contentsOf:folder.appendingPathComponent("direction.json")))
 try DeckDirector.validate(direction,count:slides.count)
 if mode=="pages" {
  let records=slides.indices.map {i in
   let points=SourceExtractor.points(slides[i],index:i+1)
   let prompt=buildPrompt(page:i)+DeckDirector.pageContext(i+1,direction:direction,slides:slides)
   let request=OllamaGenerateRequest(model:"qwen3.5:9b",prompt:prompt,system:defaultInstructions,format:OllamaSchema(ids:points.map(\\.id),comparisonIDs:SourceExtractor.comparisonIDs(points,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count))),stream:false,think:false,options:OllamaOptions(temperature:temperature,num_predict:768,num_ctx:16384,top_p:0.8,top_k:20,min_p:0,presence_penalty:1.5,repeat_penalty:1))
   return Record(slideIndex:i+1,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count),points:points,request:request)
  }
  try encoder.encode(records).write(to:folder.appendingPathComponent("requests.json"))
 } else {
  let requests=try JSONDecoder().decode([ReadRecord].self,from:Data(contentsOf:folder.appendingPathComponent("requests.json")))
  let saved=try JSONDecoder().decode([Saved].self,from:Data(contentsOf:folder.appendingPathComponent("records.json")))
  var pages:[PageBrief]=[]
  var errors:[String:String]=[:]
  for r in saved {
   do {
    if r.response.done_reason=="length" {throw OllamaError.decodeFailed("truncated")}
    let q=requests.first {$0.slideIndex==r.slideIndex}!
    let selection=try JSONDecoder().decode(ExtractiveSelection.self,from:r.response.response.data(using:.utf8)!)
    let brief=try SourceExtractor.brief(selection,points:q.points,roleHint:q.roleHint,source:slides[r.slideIndex-1])
    pages.append(PageBrief(slideIndex:r.slideIndex,brief:DeckDirector.apply(brief,page:r.slideIndex,direction:direction,slides:slides)))
   } catch { errors[String(r.slideIndex)]=error.localizedDescription }
  }
  try encoder.encode(pages).write(to:folder.appendingPathComponent("page-briefs.json"))
  try encoder.encode(errors).write(to:folder.appendingPathComponent("validation-errors.json"))
  if pages.count==slides.count && errors.isEmpty {
   for budget in [180,600,900] {
    let plan=try EditorialPlanner.assemble(pages,slideCount:slides.count,budget:budget)
    try encoder.encode(plan).write(to:folder.appendingPathComponent("plan-\\(budget).json"))
   }
  }
 }
}
} catch { fputs(error.localizedDescription+"\\n",stderr);exit(1) }
'''
 BUILD.mkdir(parents=True,exist_ok=True)
 (BUILD/'helper.swift').write_text(h)
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(ROOT/'.build/module-cache'),str(BUILD/'helper.swift'),'-o',str(BUILD/'helper')],check=True,cwd=ROOT)
 return hashlib.sha256(s.encode()).hexdigest()
def helper(mode,folder,deck,temp):
 r=subprocess.run([str(BUILD/'helper'),mode,str(folder),DECKS[deck],str(temp)],text=True,capture_output=True,cwd=ROOT)
 if r.returncode: raise RuntimeError(r.stderr[-2000:])
def generate(req,path):
 start=time.monotonic()
 try:
  with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:11434/api/generate',data=json.dumps(req).encode(),headers={'Content-Type':'application/json'}),timeout=180) as resp: data=json.load(resp)
  result={'request':req,'response':data,'elapsedSeconds':time.monotonic()-start}
 except Exception as e: result={'request':req,'error':str(e),'elapsedSeconds':time.monotonic()-start}
 write(path,result)
 return result

def main():
 OUT.mkdir(parents=True,exist_ok=True)
 sha=compile_helper()
 seed=42
 manifest={'startedAt':datetime.datetime.now().astimezone().isoformat(),'sourceSHA256':sha,'model':'qwen3.5:9b','temperatures':TEMPS,'seed':seed,'num_ctx':16384,'think':False,'pageMaxTokens':768,'budgets':[180,600,900],'design':'Full end-to-end direction and all pages per temperature; paired seed, shuffled sequential execution. No model weight, prompt or allocation changes. No response reuse from previous experiments.'}
 for api in ['version','ps','tags']:
  with urllib.request.urlopen('http://127.0.0.1:11434/api/'+api,timeout=10) as r: manifest['ollama_'+api]=json.load(r)
 write(OUT/'manifest.json',manifest)
 # Warm model before timings; this request is not scored.
 generate({'model':'qwen3.5:9b','prompt':'Return {}.','format':'json','think':False,'stream':False,'options':{'temperature':0,'num_ctx':16384,'num_predict':16}},OUT/'warmup.json')
 rng=random.Random(20260910)
 for deck in DECKS:
  slides=read(ROOT/f'evaluation/table-iteration/{deck}/slides.json')
  runs=[]
  order=TEMPS.copy();rng.shuffle(order)
  for temp in order:
   folder=OUT/f't{temp:g}'/deck
   write(folder/'slides.json',slides)
   helper('prepare',folder,deck,temp)
   req=read(folder/'direction-request.json');req['options']['seed']=seed;write(folder/'direction-request.json',req)
   result=generate(req,folder/'direction-response.json')
   print(f'{deck} temperature={temp:g} direction {result["elapsedSeconds"]:.1f}s',flush=True)
   try:
    if 'error' in result: raise RuntimeError(result['error'])
    if result['response'].get('done_reason')=='length': raise RuntimeError('direction truncated')
    write(folder/'direction.json',json.loads(result['response']['response']))
    helper('pages',folder,deck,temp)
    requests=read(folder/'requests.json')
    for q in requests:q['request']['options']['seed']=seed
    write(folder/'requests.json',requests)
    runs.append((temp,folder,requests))
   except Exception as e:
    write(folder/'run-error.json',{'stage':'direction','error':str(e)})
    print(f'FAILED {deck} {temp}: {e}',flush=True)
  for idx in range(len(slides)):
   order=runs.copy();rng.shuffle(order)
   for temp,folder,requests in order:
    q=requests[idx];path=folder/f'page-{idx+1:02d}.json'
    result=generate(q['request'],path);result.update({k:v for k,v in q.items() if k!='request'});write(path,result)
    print(f'{deck} page {idx+1}/{len(slides)} temperature={temp:g} {result["elapsedSeconds"]:.1f}s '+result.get('error','ok'),flush=True)
  for temp,folder,requests in runs:
   records=[read(folder/f'page-{i+1:02d}.json') for i in range(len(slides))]
   write(folder/'records.json',[r for r in records if 'response' in r])
   try:helper('assemble',folder,deck,temp)
   except Exception as e:write(folder/'run-error.json',{'stage':'assemble','error':str(e)})
   print(f'ASSEMBLED {deck} temperature={temp:g}',flush=True)
 manifest['completedAt']=datetime.datetime.now().astimezone().isoformat();write(OUT/'manifest.json',manifest)
 print('FULL COMPARISON COMPLETE',flush=True)
if __name__=='__main__':main()
