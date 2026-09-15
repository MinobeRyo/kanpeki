import json,time,urllib.request
from pathlib import Path
out=Path('evaluation/extractive-final');out.mkdir(exist_ok=True)
for record in json.load(open('evaluation/extractive-requests.json')):
 req=record['request'];start=time.monotonic()
 request=urllib.request.Request('http://127.0.0.1:11434/api/generate',json.dumps(req).encode(),{'Content-Type':'application/json'})
 with urllib.request.urlopen(request,timeout=300) as resp:r=json.load(resp)
 record.update(response=r,elapsedSeconds=time.monotonic()-start)
 (out/f"page-{record['slideIndex']:02d}.json").write_text(json.dumps(record,ensure_ascii=False,indent=2))
 print(record['slideIndex'],round(record['elapsedSeconds'],1),r['response'],flush=True)
