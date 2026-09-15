"""Transparent source-grounded checks; these are coverage probes, not semantic accuracy."""
from pathlib import Path
import json,re,statistics,unicodedata
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'evaluation/temperature-comparison'
# Frozen before inspecting benchmark page outputs. All regex groups must be present.
CHECKS={
 'wn':[
 (5,'参照元とグラフ',['(IMPORTRANGE|スマートチップ)','(地図|グラフ)']),
 (5,'決定的な共通地図',['決定的','同じ']),
 (7,'ハブと役割による読む順番',['ハブ','(役割|全体像.{0,5}起点)']),
 (7,'読む時間は本文量から算出',['(文字量|本文量)']),
 (8,'開始位置・既知度',['(開始位置|既知度)']),
 (8,'共有する順番を変えない',['順番.{0,15}変え(ない|ていません)']),
 (9,'担当者を期限順に提示',['(担当者|誰|人)','期限']),
 (9,'送信するのは人間',['(送信はしない|送るのは人間|送信は人)']),
 (10,'参照の4分類',['供給','依存','標準','参考']),
 (10,'未走査を影響なしと断定しない',['未走査','断定しない']),
 (11,'健康診断の採点対象',['鮮度','属人化']),
 (11,'今週の1件を効果と労力で選ぶ',['今週','効果','労力']),
 (12,'MCPサーバーとAIのツール呼出し',['MCPサーバー','ツールを呼']),
 (12,'GWS利用許可条件',['GWS','許可されていない']),
 (14,'共有情報は自分たちのDrive',['自分たちのDrive'])],
 'research':[
 (8,'ML移行の10件条件',['10件以上','(ML|モデル)']),
 (10,'決定要因4次元とコンテキスト5次元',['決定要因.{0,12}4次元','コンテキスト.{0,12}5次元']),
 (11,'時間5次元と履歴4次元',['時間.{0,12}5次元','履歴.{0,12}4次元']),
 (11,'未来の情報を使わない',['過去の(履歴|データ)','(のみ|防止)']),
 (12,'RF採用と10件条件',['RandomForest','10件以上']),
 (14,'4種の特徴量選択',['SHAP','PermutationImportance','RFE','フィルタ']),
 (14,'18から12へ絞って再訓練',['18','12','再訓練']),
 (17,'時系列検証によるリーケージ回避',['時系列交差検証','(リーケージ|未来の情報)']),
 (17,'比較対象モデル',['RandomForest','XGBoost','ルールベース']),
 (19,'提案手法の数値',['RF\\+SHAP.{0,15}MAE=0\\.0946']),
 (19,'比較対象の数値',['(RandomForest.{0,15}MAE=0\\.1024|ルールベース.{0,15}MAE=0\\.1400)']),
 (19,'ダミーデータという条件',['ダミーデータ','予備']),
 (19,'実データによる検証が必要',['実データ','必要']),
 (22,'単一ユーザーと自己申告の制限',['(シングルユーザー|単一ユーザー)','自己申告']),
 (22,'長期RRR未検証',['RRR','(未検証|未実施|今後の課題)'])]}
def norm(t):return re.sub(r'\s+','',unicodedata.normalize('NFKC',t))
def matches(t,patterns):return all(re.search(p,norm(t),re.I) for p in patterns)
def read(p):return json.loads(p.read_text())
def freeze():
 output={k:[{'page':p,'label':l,'patterns':r} for p,l,r in v] for k,v in CHECKS.items()}
 (OUT/'coverage-checks.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
 for deck,checks in CHECKS.items():
  src=read(ROOT/f'evaluation/table-iteration/{deck}/slides.json')
  for page,label,patterns in checks:
   assert matches(src[page-1]['body']+'\n'+src[page-1]['notes'],patterns),(deck,page,label)
 print('30/30 probes found in source slides')
def score_folder(folder,deck):
 paths=sorted(folder.glob('page-[0-9][0-9].json'))
 if not paths:return None
 records=[read(p) for p in paths]
 metrics={'pagesCompleted':len(records),'requestErrors':sum('error' in r for r in records),
 'pageElapsedSeconds':sum(r['elapsedSeconds'] for r in records),
 'truncatedPages':[r['slideIndex'] for r in records if r.get('response',{}).get('done_reason')=='length']}
 direction=folder/'direction-response.json'
 if direction.exists():metrics['elapsedSeconds']=metrics['pageElapsedSeconds']+read(direction)['elapsedSeconds']
 all_responses=[r.get('response',{}) for r in records]
 if direction.exists():all_responses.append(read(direction).get('response',{}))
 metrics['generationSeconds']=sum(r.get('eval_duration',0) for r in all_responses)/1e9
 metrics['promptEvaluationSeconds']=sum(r.get('prompt_eval_duration',0) for r in all_responses)/1e9
 metrics['outputTokens']=sum(r.get('eval_count',0) for r in all_responses)
 invalid=[];duplicates=[]
 raw={}
 for r in records:
  try:
   sel=json.loads(r['response']['response']);ids=sel['coreIDs']+sel['detailIDs'];points={p['id']:p['text'] for p in r['points']}
   if not set(ids)<=set(points): invalid.append(r['slideIndex'])
   if len(ids)!=len(set(ids)):duplicates.append(r['slideIndex'])
   raw[r['slideIndex']]='\n'.join(points.get(i,'') for i in ids)
  except Exception:invalid.append(r['slideIndex'])
 metrics.update(invalidPages=invalid,duplicateIDPages=duplicates)
 if not (folder/'plan-600.json').exists():return metrics
 plan=read(folder/'plan-600.json');ref=read(ROOT/('evaluation/wn-reference.json' if deck=='wn' else 'evaluation/second-deck/reference.json'))
 bypage={s['slideIndex']:s for s in plan['slides']}
 metrics.update(totalSeconds=sum(s['recommendedSeconds'] for s in plan['slides']),
 meanAbsoluteSecondsDifference=statistics.mean(abs(bypage[r['slideIndex']]['recommendedSeconds']-r['seconds']) for r in ref['slides']),
 skippedPages=[i for i,s in bypage.items() if s['recommendedSeconds']==0],
 retainedCharacters=sum(len(norm(s['talkingPoints'])) for s in plan['slides']))
 checks=[{'page':p,'label':l,'retained':bool(matches(bypage[p]['talkingPoints'],ps)),'rawRetained':bool(matches(raw.get(p,''),ps))} for p,l,ps in CHECKS[deck]]
 metrics.update(coveragePassed=sum(c['retained'] for c in checks),coverageTotal=len(checks),rawCoveragePassed=sum(c['rawRetained'] for c in checks),checks=checks)
 return metrics
if __name__=='__main__':
 import sys
 if '--freeze' in sys.argv:freeze()
 else:
  rows=[]
  for temp in [0,.35,.5,.7,1]:
   for deck in CHECKS:
    d=score_folder(OUT/f't{temp:g}'/deck,deck)
    if d:rows.append({'temperature':temp,'deck':deck,**d})
  (OUT/'metrics.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
  for d in rows: print({k:v for k,v in d.items() if k!='checks'})
