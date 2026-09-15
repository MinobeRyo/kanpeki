"""Evaluate page-local summaries on the supplied PPTX extraction; no reference answers in prompts."""
import json,time,urllib.request,argparse
from pathlib import Path

SYSTEM = json.load(open('evaluation/qwen3-summary/page-01.json'))['request']['system']

SCHEMA={'type':'object','required':['core','detail','omit','role','priority'],'properties':{'core':{'type':'string'},'detail':{'type':'string'},'omit':{'type':'string'},'role':{'type':'string','enum':['title','problem','overview','solution','mechanism','value','closing']},'priority':{'type':'integer','minimum':1,'maximum':5}}}

def prompt(slides,i):
 outline='\n'.join(f"{j+1}: "+next((line.strip() for line in s['body'].splitlines() if line.strip()),'画像中心のページ') for j,s in enumerate(slides))
 s=slides[i]
 return f'発表テーマ: wn\n目的: 資料の中心的な価値と技術的な工夫を初めて聞く人に伝える\n聴衆: 初めて聞く人\n全体の見出し（対象以外は要約しない）:\n{outline}\n\n対象ページ: {i+1}\n本文:\n{s["body"]}\n発表者ノート:\n{s["notes"]}\n\n対象ページのみを要約してください。'

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--model',default='qwen2.5:7b-instruct');ap.add_argument('--start',type=int,default=1);ap.add_argument('--end',type=int,default=15);ap.add_argument('--output',default='evaluation/summary-planner');ap.add_argument('--temperature',type=float,default=0.2);args=ap.parse_args()
 slides=json.load(open('evaluation/pptx-source/slides.json'));out=Path(args.output);out.mkdir(exist_ok=True)
 for i in range(args.start-1,min(args.end,len(slides))):
  path=out/f'page-{i+1:02d}.json'
  payload={'model':args.model,'system':SYSTEM,'prompt':prompt(slides,i),'stream':False,'format':SCHEMA,'options':{'temperature':args.temperature,'num_ctx':16384,'num_predict':768}}
  if args.model.startswith('qwen3'):payload['think']=False
  if args.model.startswith('qwen3.5'):
   payload['options'].update(top_p=0.8,top_k=20,min_p=0.0,presence_penalty=1.5,repeat_penalty=1.0)
  start=time.monotonic();req=urllib.request.Request('http://127.0.0.1:11434/api/generate',json.dumps(payload).encode(),{'Content-Type':'application/json'})
  with urllib.request.urlopen(req,timeout=300) as response:r=json.load(response)
  record={'slideIndex':i+1,'request':payload,'response':r,'elapsedSeconds':time.monotonic()-start}
  path.write_text(json.dumps(record,ensure_ascii=False,indent=2))
  d=json.loads(r['response']);print(i+1,round(record['elapsedSeconds'],1),d,flush=True)
if __name__=='__main__':main()
