"""Compare saved local-model runs; lexical checks assist, not replace, review."""
from pathlib import Path
import argparse,json,collections,statistics
p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);p.add_argument('--candidate',required=True);p.add_argument('--output',required=True);a=p.parse_args()
def read(folder):
 path=Path(folder);records=[json.loads(x.read_text()) for x in sorted(path.glob('page-[0-9][0-9].json'))]
 plan=json.loads((path/'plan.json').read_text()) if (path/'plan.json').exists() else None
 errors=[json.loads(x.read_text()) for x in sorted(path.glob('error-[0-9][0-9].json'))]
 latencies=[r['elapsedSeconds'] for r in records]
 duplicate=[];unknown=[];truncated=[];invalid=[]
 for r in records:
  try:
   selection=json.loads(r['response']['response']);ids=selection['coreIDs']+selection['detailIDs'];allowed={x['id'] for x in r['points']}
   if len(set(ids))!=len(ids):duplicate.append(r['slideIndex'])
   if any(x not in allowed for x in ids):unknown.append(r['slideIndex'])
  except (ValueError,KeyError,TypeError):invalid.append(r['slideIndex'])
  if r['response'].get('done_reason')=='length':truncated.append(r['slideIndex'])
 metrics={'completedPages':len(records),'elapsedSeconds':round(sum(latencies),1),'medianPageSeconds':round(statistics.median(latencies),1) if latencies else None,'duplicateIDPages':duplicate,'unknownIDPages':unknown,'invalidJSONPages':invalid,'truncatedPages':truncated,'errors':errors}
 if records:metrics['model']=records[0]['request']['model']
 if plan:
  times=[s['recommendedSeconds'] for s in plan['slides']];metrics.update(totalSeconds=sum(times),secondsHistogram=dict(collections.Counter(times)),skippedPages=[s['slideIndex'] for s in plan['slides'] if not s['recommendedSeconds']])
 return metrics,plan
b,bp=read(a.baseline);c,cp=read(a.candidate)
checks=[('19：予備評価の明示',19,['ダミー','予備']),('19：実データ検証の必要性',19,['実データ']),('19：数値比較表',19,['0.0946','0.1400']),('10：コンテキスト特徴量',10,['ストレス','空腹']),('22：長期評価の制限',22,['長期','RRR'])]
def retained(plan,page,terms):
 if not plan:return '未完了'
 text=next((s['talkingPoints'] for s in plan['slides'] if s['slideIndex']==page),'')
 return '語句あり（要確認）' if all(t in text for t in terms) else '不足'
lines=['# ローカルモデル比較','', '同じ保存済み入力・指示・生成設定でモデルを変更した単発の比較。量子化・テンプレート・ロード状態の差も含む。モデル世代だけの純粋な性能差ではない。','', '|項目|前回|今回|','|---|---|---|']
for key in ['model','completedPages','elapsedSeconds','medianPageSeconds','totalSeconds','duplicateIDPages','unknownIDPages','truncatedPages','skippedPages']:
 lines.append(f'|{key}|{b.get(key,"未完了")}|{c.get(key,"未完了")}|')
lines+=['','## 研究資料の条件保持','', '以下は語句の保持を調べる補助チェック。意味の正しさ・要約の品質を保証する精度スコアではない。','', '|チェック|前回|今回|','|---|---|---|']
for title,page,terms in checks:lines.append(f'|{title}|{retained(bp,page,terms)}|{retained(cp,page,terms)}|')
if bp and cp:
 lines+=['','## 時間配分','', '|ページ|前回（秒）|今回（秒）|','|---|---:|---:|']
 for x,y in zip(bp['slides'],cp['slides']):lines.append(f'|{x["slideIndex"]}|{x["recommendedSeconds"]}|{y["recommendedSeconds"]}|')
output=Path(a.output);output.write_text('\n'.join(lines)+'\n');output.with_suffix('.json').write_text(json.dumps({'baseline':b,'candidate':c},ensure_ascii=False,indent=2))
print(output)
