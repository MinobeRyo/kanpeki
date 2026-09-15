"""Evaluate a PPTX using the production parser, prompts, schema and planner.
prepare/assemble are offline; run sends only to local Ollama.
"""
from pathlib import Path
import argparse,json,re,subprocess,time,urllib.request,urllib.error
p=argparse.ArgumentParser();p.add_argument('mode',choices=['prepare','run','assemble']);p.add_argument('--pptx');p.add_argument('--out',required=True);p.add_argument('--budget',type=int,default=600);p.add_argument('--theme',default='');p.add_argument('--model',default='qwen3.5:9b');p.add_argument('--pages',type=int,nargs='*');p.add_argument('--resume',action='store_true');a=p.parse_args()
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
if a.mode=='run':
 for record in json.loads((out/'requests.json').read_text()):
  if a.pages and record['slideIndex'] not in a.pages:continue
  saved=out/f"page-{record['slideIndex']:02d}.json"
  if a.resume and saved.exists():
   previous=json.loads(saved.read_text())
   if all(previous.get(k)==record.get(k) for k in ('request','points','roleHint')):continue
  start=time.monotonic();req=urllib.request.Request('http://127.0.0.1:11434/api/generate',json.dumps(record['request']).encode(),{'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=300) as response:result=json.load(response)
  except (urllib.error.HTTPError,urllib.error.URLError,TimeoutError) as error:
   detail=error.read().decode() if isinstance(error,urllib.error.HTTPError) else str(error)
   (out/f"error-{record['slideIndex']:02d}.json").write_text(json.dumps({'request':record['request'],'error':detail,'elapsedSeconds':time.monotonic()-start},ensure_ascii=False,indent=2))
   raise SystemExit(detail)
  record.update(response=result,elapsedSeconds=time.monotonic()-start)
  (out/f"page-{record['slideIndex']:02d}.json").write_text(json.dumps(record,ensure_ascii=False,indent=2))
  print(record['slideIndex'],round(record['elapsedSeconds'],1),result['response'],flush=True)
else:
 s=Path('SlidePacer/ContentView.swift').read_text()
 source=s[s.index('struct SlideInput:'):s.index('// MARK: - JSON取り込み用モデル')]
 models=s[s.index('@Generable(description: "1枚'):s.index('enum OllamaClient')]
 models=re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n','',models).replace('private ', '')
 instructions=s[s.index('let defaultInstructions ='):s.index('// MARK: - ContentView')]
 prompt=s[s.index('    private func buildPrompt('):s.index('    private func runAnalysis()')].replace('private func','func')
 harness='import Foundation\nimport Compression\n'+source+models+instructions+'''
let out = URL(fileURLWithPath: CommandLine.arguments[1])
struct Record: Codable {
 let slideIndex: Int
 let roleHint: String?
 let points: [SourcePoint]
 let request: OllamaGenerateRequest
}
'''
 if a.mode=='prepare':
  harness+='''
let slides = try PPTXReader.loadSlides(from: URL(fileURLWithPath: CommandLine.arguments[2]))
let theme = CommandLine.arguments[3]
let presentationGoal = ""
let audience = ""
'''+prompt+'''
var records: [Record] = []
for i in slides.indices {
 let points = SourceExtractor.points(slides[i], index: i+1)
 let request = OllamaGenerateRequest(model: CommandLine.arguments[4], prompt: buildPrompt(page:i), system:defaultInstructions, format:OllamaSchema(ids:points.map(\\.id),comparisonIDs:SourceExtractor.comparisonIDs(points,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count))), stream:false, think:false, options:OllamaOptions(temperature:0.7,num_predict:768,num_ctx:16384,top_p:0.8,top_k:20,min_p:0,presence_penalty:1.5,repeat_penalty:1))
 records.append(Record(slideIndex:i+1,roleHint:SourceExtractor.roleHint(slides[i],index:i+1,count:slides.count),points:points,request:request))
}
try JSONEncoder().encode(records).write(to:out.appendingPathComponent("requests.json"))
try JSONSerialization.data(withJSONObject:slides.enumerated().map{["slideIndex":$0.offset+1,"body":$0.element.body,"notes":$0.element.notes]},options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("slides.json"))
print("Prepared \\(slides.count) pages")
'''
  # Request structs need Encodable only, as in production.
  harness=harness.replace('struct Record: Codable','struct Record: Encodable')
 else:
  records=[json.loads(p.read_text()) for p in sorted(out.glob('page-[0-9][0-9].json'))]
  (out/'records.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
  harness=harness[:harness.index('struct Record:')]+'''
struct Record: Decodable {
 let slideIndex:Int; let roleHint:String?; let points:[SourcePoint]; let response:Response
 struct Response:Decodable {let response:String;let done_reason:String?}
}
let records = try JSONDecoder().decode([Record].self,from:Data(contentsOf:out.appendingPathComponent("records.json")))
let raw = try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("slides.json"))) as! [[String:Any]]
let slides = raw.map {SlideInput(body:$0["body"] as! String,notes:$0["notes"] as! String)}
let pages = try records.map { r in
 if r.response.done_reason == "length" {throw OllamaError.decodeFailed("Truncated response")}
 let selection = try JSONDecoder().decode(ExtractiveSelection.self,from:r.response.response.data(using:.utf8)!)
 return PageBrief(slideIndex:r.slideIndex,brief:try SourceExtractor.brief(selection,points:r.points,roleHint:r.roleHint,source:slides[r.slideIndex-1]))
}
let plan = try EditorialPlanner.assemble(pages,slideCount:slides.count,budget:Int(CommandLine.arguments[2])!)
try JSONEncoder().encode(pages).write(to:out.appendingPathComponent("page-briefs.json"))
try JSONEncoder().encode(plan).write(to:out.appendingPathComponent("plan.json"))
print("Total \\(plan.slides.reduce(0){$0+$1.recommendedSeconds}) seconds")
'''
 build=Path('.build');build.mkdir(exist_ok=True);file=build/'evaluate-deck.swift';file.write_text(harness)
 subprocess.run(['xcrun','swift','-module-cache-path',str(build/'module-cache'),str(file),str(out),a.pptx if a.mode=='prepare' else str(a.budget),a.theme or (Path(a.pptx).stem if a.pptx else ''),a.model],check=True)
