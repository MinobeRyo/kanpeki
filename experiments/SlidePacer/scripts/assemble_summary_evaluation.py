"""Assemble real page summaries with the app's production allocator."""
import argparse,json,re,subprocess
from pathlib import Path
ap=argparse.ArgumentParser();ap.add_argument('directory');args=ap.parse_args()
source=Path('SlidePacer/ContentView.swift').read_text()
models=source[source.index('@Generable(description: "1枚'):source.index('enum OllamaClient')]
models=re.sub(r'@(?:Guide|Generable)(?:\([^\n]*\))?\n','',models)
records=[json.load(open(p)) for p in sorted(Path(args.directory).glob('page-[0-9][0-9].json'))]
pages=[{'slideIndex':r['slideIndex'],'brief':json.loads(r['response']['response'])} for r in records]
assert len(pages)==15
out=Path(args.directory);(out/'page-briefs.json').write_text(json.dumps(pages,ensure_ascii=False,indent=2))
build=Path('.build');build.mkdir(exist_ok=True)
# Paths enter Swift via JSON string literals, never via the shell.
input_path=json.dumps(str((out/'page-briefs.json').resolve()))
output_path=json.dumps(str((out/'plan.json').resolve()))
swift='import Foundation\n'+source[source.index('struct SlideInput:'):source.index('// MARK: - PPTX')]+models+f"""
let pages = try JSONDecoder().decode([PageBrief].self, from: Data(contentsOf: URL(fileURLWithPath: {input_path})))
let plan = try EditorialPlanner.assemble(pages, slideCount: 15, budget: 600)
try JSONEncoder().encode(plan).write(to: URL(fileURLWithPath: {output_path}))
"""
script=build/'assemble-summary.swift';script.write_text(swift)
subprocess.run(['xcrun','swift','-module-cache-path',str(build/'module-cache'),str(script)],check=True)
plan=json.load(open(out/'plan.json'));reference=json.load(open('evaluation/wn-reference.json'))
print('Total:',sum(p['recommendedSeconds'] for p in plan['slides']))
for p,g in zip(plan['slides'],reference['slides']):
 print(p['slideIndex'],p['recommendedSeconds'],'reference',g['seconds'],p['treatment'],p['talkingPoints'])
print('Elapsed:',round(sum(r['elapsedSeconds'] for r in records),1),'seconds')
