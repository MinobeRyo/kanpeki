from pathlib import Path
import json,re,subprocess
source=Path('SlidePacer/ContentView.swift').read_text()
models=source[source.index('@Generable(description: "1枚'):source.index('enum OllamaClient')]
models=re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n','',models)
slide=source[source.index('struct SlideInput:'):source.index('// MARK: - PPTX')]
records=[json.load(open(p)) for p in sorted(Path('evaluation/extractive-final').glob('page-[0-9][0-9].json'))]
Path('evaluation/extractive-final/records.json').write_text(json.dumps(records,ensure_ascii=False))
h='import Foundation\n'+slide+models+'''
struct Record: Decodable {
    let slideIndex: Int
    let roleHint: String?
    let points: [SourcePoint]
    let response: Response
    struct Response: Decodable { let response: String }
}
let records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: URL(fileURLWithPath: "evaluation/extractive-final/records.json")))
let rawSlides = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "evaluation/pptx-source/slides.json"))) as! [[String: Any]]
let slides = rawSlides.map { SlideInput(body: $0["body"] as! String, notes: $0["notes"] as! String) }
let pages = try records.map { record in
    let selection = try JSONDecoder().decode(ExtractiveSelection.self, from: record.response.response.data(using: .utf8)!)
    return PageBrief(slideIndex: record.slideIndex, brief: try SourceExtractor.brief(selection, points: record.points, roleHint: record.roleHint, source: slides[record.slideIndex - 1]))
}
let plan = try EditorialPlanner.assemble(pages, slideCount: 15, budget: 600)
try JSONEncoder().encode(plan).write(to: URL(fileURLWithPath: "evaluation/extractive-final/plan.json"))
try JSONEncoder().encode(pages).write(to: URL(fileURLWithPath: "evaluation/extractive-final/page-briefs.json"))
let short = try EditorialPlanner.assemble(pages, slideCount: 15, budget: 180)
try JSONEncoder().encode(short).write(to: URL(fileURLWithPath: "evaluation/extractive-final/plan-180.json"))
'''
script=Path('.build/assemble-extractive.swift');script.parent.mkdir(exist_ok=True);script.write_text(h)
subprocess.run(['xcrun','swift','-module-cache-path','.build/module-cache',str(script)],check=True)
plan=json.load(open('evaluation/extractive-final/plan.json'))
print('Total',sum(s['recommendedSeconds'] for s in plan['slides']),'elapsed',round(sum(r['elapsedSeconds'] for r in records),1))
for s in plan['slides']:print(s['slideIndex'],s['recommendedSeconds'],s['treatment'],s['talkingPoints'])
