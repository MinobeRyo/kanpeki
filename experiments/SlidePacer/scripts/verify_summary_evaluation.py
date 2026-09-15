import argparse,json,time,urllib.request
from pathlib import Path
SYSTEM='''あなたは資料要約の校正者です。原文と要約案を照合し、正確な要約に直してください。
特に「何が変わり、何が変わらないか」「誰が何として動作するか」「自動で行うか人が行うか」「必要な権限・条件」「数式の意味」を確認します。主語や否定を逆転させないでください。
原文にない内容や曖昧な因果関係は削除します。原文の重要な設計意図・具体的な機能を残します。専門語と日本語の誤字も直します。
coreは必ず伝える主張、detailは追加の仕組み・根拠・条件、omitは省く細部です。coreとdetailの重複を避けます。
roleはtitle（表紙）/problem（課題）/overview（機能一覧・目次）/solution（解決策）/mechanism（仕組み・技術）/value（効果・設計方針）/closing（謝辞）。課題を解決する機能のページをproblemにしない。機能一覧を個別機能と混同しない。
priorityは表紙・謝辞1〜2、一覧2〜3、課題3〜4、解決策と根拠4〜5を目安とします。
原文の情報だけで修正し、core,detail,omit,role,priorityのJSONだけ返してください。'''
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--source',default='evaluation/qwen3-summary');ap.add_argument('--output',default='evaluation/qwen3-verified');args=ap.parse_args();out=Path(args.output);out.mkdir(exist_ok=True)
 for path in sorted(Path(args.source).glob('page-[0-9][0-9].json')):
  d=json.load(open(path));req=d['request'].copy();req['system']=SYSTEM;req['prompt']+='\n要約案:\n'+d['response']['response'];start=time.monotonic()
  request=urllib.request.Request('http://127.0.0.1:11434/api/generate',json.dumps(req).encode(),{'Content-Type':'application/json'})
  with urllib.request.urlopen(request,timeout=300) as resp:r=json.load(resp)
  result={'slideIndex':d['slideIndex'],'request':req,'response':r,'elapsedSeconds':time.monotonic()-start}
  (out/path.name).write_text(json.dumps(result,ensure_ascii=False,indent=2));print(d['slideIndex'],round(result['elapsedSeconds'],1),r['response'],flush=True)
if __name__=='__main__':main()
