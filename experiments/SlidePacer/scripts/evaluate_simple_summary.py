"""Evaluate page-local summaries on the supplied PPTX extraction; no reference answers in prompts."""
import json,time,urllib.request,argparse
from pathlib import Path

_source = Path('SlidePacer/ContentView.swift').read_text()
SYSTEM = "対象の1ページの本文と発表者ノートを両方読み、日本語で120〜200文字程度に要約してください。機能名だけでなく、できること・仕組み・設計意図や条件を含めてください。本文とノートは互いを補完します。情報を他ページから足さず、資料にない事実を作らないでください。表紙と謝辞は短くて構いません。summaryの1項目だけのJSONを返してください。"

SCHEMA={'type':'object','required':['summary'],'properties':{'summary':{'type':'string'}}}

def prompt(slides,i):
 outline='\n'.join(f"{j+1}: "+next((line.strip() for line in s['body'].splitlines() if line.strip()),'画像中心のページ') for j,s in enumerate(slides))
 s=slides[i]
 return f'発表テーマ: wn\n目的: 資料の中心的な価値と技術的な工夫を初めて聞く人に伝える\n聴衆: 初めて聞く人\n対象ページ: {i+1}\n本文:\n{s["body"]}\n発表者ノート:\n{s["notes"]}\n\n対象ページのみを要約してください。'

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--model',default='qwen2.5:7b-instruct');ap.add_argument('--start',type=int,default=1);ap.add_argument('--end',type=int,default=15);args=ap.parse_args()
 slides=json.load(open('evaluation/pptx-source/slides.json'));out=Path('evaluation/summary-simple');out.mkdir(exist_ok=True)
 for i in [0,1,4,7,8,11]:
  path=out/f'page-{i+1:02d}.json'
  payload={'model':args.model,'system':SYSTEM,'prompt':prompt(slides,i),'stream':False,'format':SCHEMA,'options':{'temperature':0.2,'num_ctx':16384,'num_predict':768}}
  if args.model.startswith('qwen3:'):payload['think']=False
  start=time.monotonic();req=urllib.request.Request('http://127.0.0.1:11434/api/generate',json.dumps(payload).encode(),{'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=300) as response:r=json.load(response)
  record={'slideIndex':i+1,'request':payload,'response':r,'elapsedSeconds':time.monotonic()-start}
  path.write_text(json.dumps(record,ensure_ascii=False,indent=2))
  d=json.loads(r['response']);print(i+1,round(record['elapsedSeconds'],1),d,flush=True)
if __name__=='__main__':main()
