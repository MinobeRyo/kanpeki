"""Evaluate production deck-wide ranking plus page selections on saved slide inputs."""
from pathlib import Path
import argparse,json,re,subprocess,urllib.request,time
p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','direct','pages','assemble']);p.add_argument('--input',required=True);p.add_argument('--out',required=True);p.add_argument('--theme',default='');p.add_argument('--budget',type=int,default=600);p.add_argument('--plan-name',default='plan.json');a=p.parse_args()
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True);inp=Path(a.input).resolve()
if a.mode=='direct':
 req=json.loads((out/'direction-request.json').read_text());start=time.monotonic()
 with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:11434/api/generate',data=json.dumps(req).encode(),headers={'Content-Type':'application/json'}),timeout=300) as r:response=json.load(r)
 (out/'direction-response.json').write_text(json.dumps(response,ensure_ascii=False,indent=2))
 (out/'direction-timing.json').write_text(json.dumps({'elapsedSeconds':time.monotonic()-start}))
 if response.get('done_reason')=='length':raise SystemExit('Direction output truncated')
 (out/'direction.json').write_text(json.dumps(json.loads(response['response']),ensure_ascii=False,indent=2));print(response['response'])
else:
 s=Path('SlidePacer/ContentView.swift').read_text();models=s[s.index('@Generable(description: "1枚'):s.index('enum OllamaClient')];models=re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n','',models).replace('private ','')
 slide=s[s.index('struct SlideInput:'):s.index('// MARK: - PPTX')];instructions=s[s.index('let defaultInstructions ='):s.index('// MARK: - ContentView')];prompt=s[s.index('    private func buildPrompt('):s.index('    private func runAnalysis()')].replace('private func','func')
 h='import Foundation\n'+slide+models+instructions+'''
let out=URL(fileURLWithPath:CommandLine.arguments[1])
let input=URL(fileURLWithPath:CommandLine.arguments[2])
let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:input)) as! [[String:Any]]
let slides=raw.map {SlideInput(body:$0["body"] as! String,notes:$0["notes"] as! String)}
let theme=CommandLine.arguments[3]
let presentationGoal=""
let audience=""
'''+prompt
 if a.mode=='prepare':
  h+='''
let prompt=DeckDirector.prompt(slides:slides,theme:theme,goal:presentationGoal,audience:audience)
let request=DeckDirector.request(model:"qwen3.5:9b",prompt:prompt,count:slides.count,temperature:0.7,context:16384)
try JSONSerialization.data(withJSONObject:request,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("direction-request.json"))
try Data(contentsOf:input).write(to:out.appendingPathComponent("slides.json"))
'''
 else:
  h+='''
let direction=try JSONDecoder().decode(DeckDirection.self,from:Data(contentsOf:out.appendingPathComponent("direction.json")))
try DeckDirector.validate(direction,count:slides.count)
'''
  if a.mode=='pages':
   h+='''
struct Record:Encodable {let slideIndex:Int;let roleHint:String?;let points:[SourcePoint];let request:OllamaGenerateRequest}
let records=slides.indices.map {i in
 let points=SourceExtractor.points(slides[i],index:i+1)
 let prompt=buildPrompt(page:i)+DeckDirector.pageContext(i+1,direction:direction,slides:slides)
 let request=OllamaGenerateRequest(model:"qwen3.5:9b",prompt:prompt,system:defaultInstructions,format:OllamaSchema(ids:points.map(\\.id),comparisonIDs:SourceExtractor.comparisonIDs(points,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count))),stream:false,think:false,options:OllamaOptions(temperature:0.7,num_predict:768,num_ctx:16384,top_p:0.8,top_k:20,min_p:0,presence_penalty:1.5,repeat_penalty:1))
 return Record(slideIndex:i+1,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count),points:points,request:request)
}
try JSONEncoder().encode(records).write(to:out.appendingPathComponent("requests.json"))
'''
  else:
   records=[json.loads(p.read_text()) for p in sorted(out.glob('page-[0-9][0-9].json'))]
   requests=json.loads((out/'requests.json').read_text())
   if len(records)!=len(requests) or any(any(r.get(k)!=q.get(k) for k in ('slideIndex','request','points','roleHint')) for r,q in zip(records,requests)):
    raise SystemExit('Saved responses do not match current requests. Rerun changed pages before assembling.')
   (out/'records.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
   h+='''
struct Record:Decodable {let slideIndex:Int;let roleHint:String?;let points:[SourcePoint];let response:Response;struct Response:Decodable {let response:String;let done_reason:String?}}
let records=try JSONDecoder().decode([Record].self,from:Data(contentsOf:out.appendingPathComponent("records.json")))
let pages=try records.map {r in
 if r.response.done_reason == "length" {throw OllamaError.decodeFailed("truncated")}
 let selection=try JSONDecoder().decode(ExtractiveSelection.self,from:r.response.response.data(using:.utf8)!)
 let brief=try SourceExtractor.brief(selection,points:r.points,roleHint:r.roleHint,source:slides[r.slideIndex-1])
 return PageBrief(slideIndex:r.slideIndex,brief:DeckDirector.apply(brief,page:r.slideIndex,direction:direction,slides:slides))
}
let plan=try EditorialPlanner.assemble(pages,slideCount:slides.count,budget:Int(CommandLine.arguments[4])!)
try JSONEncoder().encode(pages).write(to:out.appendingPathComponent("page-briefs.json"))
try JSONEncoder().encode(plan).write(to:out.appendingPathComponent(CommandLine.arguments[5]))
print(plan.slides.map {"\\($0.slideIndex):\\($0.recommendedSeconds)"}.joined(separator:", "))
'''
 build=Path('.build');build.mkdir(exist_ok=True);f=build/'evaluate-global.swift';f.write_text(h)
 subprocess.run(['xcrun','swift','-module-cache-path',str(build/'module-cache'),str(f),str(out),str(inp),a.theme,str(a.budget),a.plan_name],check=True)
