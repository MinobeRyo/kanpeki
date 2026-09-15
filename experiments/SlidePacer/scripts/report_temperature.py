"""Produce a reviewable report from the completed local temperature experiment."""
from pathlib import Path
import json,statistics,hashlib
from score_temperature import OUT,ROOT,CHECKS,score_folder,read
TEMPS=[0,.35,.5,.7,1]
rows=[]
for temp in TEMPS:
 for deck in CHECKS:
  m=score_folder(OUT/f't{temp:g}'/deck,deck)
  if m:rows.append({'temperature':temp,'deck':deck,**m})
(OUT/'metrics.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
aggregates=[]
for temp in TEMPS:
 ds=[r for r in rows if r['temperature']==temp]
 if len(ds)!=2 or any('coveragePassed' not in d for d in ds):continue
 a={'temperature':temp,'coveragePassed':sum(d['coveragePassed'] for d in ds),'coverageTotal':30,'rawCoveragePassed':sum(d['rawCoveragePassed'] for d in ds),'retainedCharacters':sum(d['retainedCharacters'] for d in ds),'elapsedSeconds':sum(d['elapsedSeconds'] for d in ds),'meanAbsoluteSecondsDifference':sum(d['meanAbsoluteSecondsDifference']*d['pagesCompleted'] for d in ds)/40,'errors':sum(d['requestErrors']+len(d['invalidPages'])+len(d['truncatedPages']) for d in ds)}
 a['generationSeconds']=sum(d['generationSeconds'] for d in ds)
 a['promptEvaluationSeconds']=sum(d['promptEvaluationSeconds'] for d in ds)
 for d in ds:a[d['deck']+'MAE']=d['meanAbsoluteSecondsDifference']
 aggregates.append(a)
(OUT/'aggregate.json').write_text(json.dumps(aggregates,ensure_ascii=False,indent=2))
lines=['# ローカルQwenのTemperature比較','',
 '同じQwen3.5:9b、同じ2資料、同じプロンプト・補完・時間配分処理で比較。初回は各条件で全体判定と全40ページを新規生成した。seed=42を固定。モデルの重みは変更していない。','',
 '|Temperature|表示に残った重要事項|LLM選択時点|配分案との差 WN|配分案との差 研究|2資料の推論時間|',
 '|---|---:|---:|---:|---:|---:|']
for a in aggregates:
 lines.append(f'|{a["temperature"]:g}|{a["coveragePassed"]}/30|{a["rawCoveragePassed"]}/30|{a["wnMAE"]:.1f}秒/頁|{a["researchMAE"]:.1f}秒/頁|{a["elapsedSeconds"]/60:.1f}分|')
lines+=['','「重要事項」は事前に定義した30項目の保持チェック。一般的な正解率ではなく、条件補完後のアプリ全体の結果とLLMの原文選択段階を分けている。配分案との差は、事前に作った編集案との平均絶対秒差で、要約の正解率でも実測話速でもない。','',
 '時間は全体比較とページ推論のHTTP待ち時間の合計。初期ロード用ウォームアップ、Swift処理、UI操作を含まない。実行順を入れ替えているが、Ollamaの内部キャッシュやOS負荷は完全には揃わないため、小差を速度の優劣とは断定しない。','',
 '## 条件ごとの欠落と配分','']
lines += ['入力評価・生成の内訳（Ollama計測）：','', '|Temperature|入力評価|出力生成|', '|---|---:|---:|']
for a in aggregates:lines.append(f'|{a["temperature"]:g}|{a["promptEvaluationSeconds"]:.1f}秒|{a["generationSeconds"]:.1f}秒|')
lines += ['', '全体入力を最初に評価した0.35には入力キャッシュ未作成の時間が偏っている。このHTTP所要時間差をtemperature自体の速度差とは扱わない。', '']
for d in rows:
 lines += [f'### Temperature {d["temperature"]:g} / {d["deck"]}','']
 if 'checks' not in d:
  lines.append('未完了または構造検証失敗。詳細は保存した応答・エラーを参照。');continue
 missed=[f'{c["page"]}頁：{c["label"]}' for c in d['checks'] if not c['retained']]
 lines+=['重要事項チェックの未達：'+('、'.join(missed) if missed else 'なし'),'',f'採用文字数（空白を除く）：{d["retainedCharacters"]}。600秒時の省略ページ：{d["skippedPages"]}。', '', '|時間上限|配分合計|省略ページ|','|---:|---:|---|']
 folder=OUT/f't{d["temperature"]:g}'/d['deck']
 for budget in [180,600,900]:
  plan=read(folder/f'plan-{budget}.json');ss=plan['slides']
  lines.append(f'|{budget}秒|{sum(s["recommendedSeconds"] for s in ss)}秒|{[s["slideIndex"] for s in ss if s["recommendedSeconds"]==0]}|')
 lines+=['',f'HTTP失敗{d["requestErrors"]}、未知ID/JSON不正{len(d["invalidPages"])}、生成打切り{len(d["truncatedPages"])}。重複IDは{d["duplicateIDPages"]}頁（アプリの統合処理前）。','']
lines+=['## 記録','', '[評価条件](method.md)、[重要事項の判定式](coverage-checks.json)、[集計JSON](metrics.json)。各temperature/deckフォルダに入力・全リクエスト・全応答・配分を保存。','',
 'この2資料はこれまで調整にも使用した資料。未知資料、画面キャプチャ/OCR、別モデル、別マシンへの一般化は未検証。意味の矛盾検出や冗長さの完全な評価も含まない。']
(OUT/'comparison.md').write_text('\n'.join(lines)+'\n')
# Side-by-side timing and full retained text, available for human review.
for deck in CHECKS:
 ref=read(ROOT/('evaluation/wn-reference.json' if deck=='wn' else 'evaluation/second-deck/reference.json'))
 review=[f'# {deck} 条件別の要点と時間配分','']
 for r in ref['slides']:
  i=r['slideIndex'];review += [f'## {i}ページ','',f'比較用編集案：{r["seconds"]}秒。{r["summary"]}','']
  for t in TEMPS:
   file=OUT/f't{t:g}'/deck/'plan-600.json'
   if not file.exists():continue
   s=next(s for s in read(file)['slides'] if s['slideIndex']==i)
   review += [f'### Temperature {t:g}：{s["recommendedSeconds"]}秒 / {s["treatment"]}','',s['talkingPoints'] or '（省略）','']
 (OUT/f'{deck}-content.md').write_text('\n'.join(review)+'\n')
print(json.dumps(aggregates,ensure_ascii=False,indent=2))
