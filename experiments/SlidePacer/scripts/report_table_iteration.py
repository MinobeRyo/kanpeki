"""Report the table/segmentation change against the preceding saved run."""
from pathlib import Path
import json,statistics,hashlib
root=Path('evaluation/table-iteration')
cases=[('WN','wn','evaluation/wn-reference.json'),('研究資料','research','evaluation/second-deck/reference.json')]
lines=['# 表の比較と要点の粒度を改善した評価','',
'Qwen3.5:9bで同じ元PPTXの40ページを再実行。全体の重点候補は前回の応答を固定し、表の読み込み・原文候補の粒度・ページ選択の指示と出力条件を変更した。モデルの重みは変更していない。', '',
'今回の配分処理は前回と同じ。入力の空行の正規化と表の整形を含む。元PPTXと数値列の対応を照合した結果は parser-audit.json に保存。', '',
'|資料|平均秒差／頁（前回→今回）|採用要点の総文字数（前回→今回）|合計|', '|---|---:|---:|---:|']
detail=[]
for label,name,refpath in cases:
 out=root/name
 read=lambda path: json.loads(Path(path).read_text())
 previous=read('evaluation/20260910/'+name+'/result.json')
 plan=read(out/'plan.json');records=read(out/'records.json');requests=read(out/'requests.json');ref=read(refpath)
 assert len(records)==len(requests)==len(ref['slides'])
 assert all(r['request']==q['request'] for r,q in zip(records,requests))
 valid=[]
 for r in records:
  selection=json.loads(r['response']['response']);schema=r['request']['format']['properties']['coreIDs']
  assert r['response'].get('done_reason')!='length'
  assert set(selection['coreIDs']+selection['detailIDs']) <= {p['id'] for p in r['points']}
  if schema['minItems']==2:
   assert len(set(selection['coreIDs']))==2
   assert set(selection['coreIDs']) <= set(schema['items']['enum'])
   valid.append(r['slideIndex'])
 def seconds_error(plan):return statistics.mean(abs(s['recommendedSeconds']-r['seconds']) for s,r in zip(plan['slides'],ref['slides']))
 def chars(plan):return sum(len(s['talkingPoints']) for s in plan['slides'])
 total=sum(s['recommendedSeconds'] for s in plan['slides']);assert total==600
 metrics={'previousMeanAbsoluteSecondsDifference':seconds_error(previous['plan']),'meanAbsoluteSecondsDifference':seconds_error(plan),
 'previousTalkingPointCharacters':chars(previous['plan']),'talkingPointCharacters':chars(plan),'totalSeconds':total,
 'constrainedComparisonPages':valid,'pageGenerationElapsedSeconds':sum(r['elapsedSeconds'] for r in records),
 'skippedPages':[s['slideIndex'] for s in plan['slides'] if not s['recommendedSeconds']]}
 result={'status':'evaluated-table-and-segmentation-iteration','model':'qwen3.5:9b','budgetSeconds':600,
 'codeSHA256':hashlib.sha256(Path('SlidePacer/ContentView.swift').read_bytes()).hexdigest(),
 'input':read(out/'slides.json'),'direction':read(out/'direction.json'),'pageRecords':records,'pageBriefs':read(out/'page-briefs.json'),
 'plan':plan,'evaluation':metrics,'limitations':'Two tuning decks; no OCR or unseen-deck test. Time slots are not measured reading times. The two-row comparison constraint is code-assisted.'}
 (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
 lines.append(f'|{label}|{seconds_error(previous["plan"]):.1f}秒 → {seconds_error(plan):.1f}秒|{chars(previous["plan"]):,} → {chars(plan):,}|{total}秒|')
 detail += ['',f'## {label}の配分','','|頁|人の基準|前回|今回|','|---|---:|---:|---:|']
 for r,p,n in zip(ref['slides'],previous['plan']['slides'],plan['slides']):detail.append(f'|{r["slideIndex"]}|{r["seconds"]}|{p["recommendedSeconds"]}|{n["recommendedSeconds"]}|')
lines += ['', '平均秒差は人の編集案との距離であり、要約の正解率ではない。文字量の減少だけでも品質は判定できない。意味の保持と残る問題は [content-review.md](content-review.md) に記載。', '',
'数値比較がある結果ページでは、複数の数値指標を持つ同一表から異なる2行を選ぶ条件をコードで設定した。行の選択自体はQwenが行う。数字を人の基準から注入したり、事後に正解の行へ置き換えたりはしていない。', '',
'ネイティブ表の行・列を利用するため、画像や文字ボックスだけで作られた表にはこの整形は適用されない。firstRow指定のない表の列名は、複数列で「文字の見出し→数値の列」が揃うときのみ推定する。結合セルなどは推定せず従来の本文抽出に戻す。', '',
'30件の回帰テストとSwift全体の型チェックを実施。比較行・数値の対応、ヘッダーなしの表、結合セル、XML文字参照、比較行の重複を確認した。']
(root/'comparison.md').write_text('\n'.join(lines+detail)+'\n')
print(root/'comparison.md')
