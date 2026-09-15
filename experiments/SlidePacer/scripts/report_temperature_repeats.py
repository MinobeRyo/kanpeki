"""Summarize page-level repetitions without pretending they are repeated full-deck runs."""
import json,itertools,statistics
from score_temperature import OUT,CHECKS,read,matches
manifest=read(OUT/'repeats/manifest.json')
rows=[]
for temp in manifest['temperatures']:
 for deck,indices in manifest['pages'].items():
  for page in indices:
   runs=[]
   for seed in [42,43,44]:
    folder=OUT/f't{temp:g}'/deck if seed==42 else OUT/'repeats'/f't{temp:g}'/f'seed-{seed}'/deck
    record=read(folder/f'page-{page:02d}.json')
    if 'response' not in record:runs.append({'seed':seed,'error':record.get('error')});continue
    selection=json.loads(record['response']['response'])
    briefs=read(folder/'page-briefs.json');brief=next((p['brief'] for p in briefs if p['slideIndex']==page),None)
    if brief is None:runs.append({'seed':seed,'error':'validation failed'});continue
    relevant=[(label,patterns) for p,label,patterns in CHECKS[deck] if p==page]
    text=brief['core']+'\n'+brief['detail']
    runs.append({'seed':seed,'selection':selection,'brief':brief,'checks':[{'label':label,'retained':bool(matches(text,ps))} for label,ps in relevant]})
   valid=[r for r in runs if 'selection' in r]
   pairs=[]
   for a,b in itertools.combinations(valid,2):
    aa=set(a['selection']['coreIDs']+a['selection']['detailIDs']);bb=set(b['selection']['coreIDs']+b['selection']['detailIDs'])
    pairs.append(len(aa&bb)/len(aa|bb) if aa|bb else 1)
   rows.append({'temperature':temp,'deck':deck,'page':page,'runs':runs,'meanPairwiseIDJaccard':statistics.mean(pairs) if pairs else None,'sameRole':len({r['selection']['role'] for r in valid})==1,'samePriority':len({r['selection']['priority'] for r in valid})==1})
aggregate=[]
for temp in manifest['temperatures']:
 ds=[r for r in rows if r['temperature']==temp]
 rr=[run for r in ds for run in r['runs']]
 aggregate.append({'temperature':temp,'attempts':len(rr),'errors':sum('error' in run for run in rr),'coveredChecks':sum(c['retained'] for run in rr for c in run.get('checks',[])),'totalChecks':sum(len(run.get('checks',[])) for run in rr),'meanPairwiseIDJaccard':statistics.mean(d['meanPairwiseIDJaccard'] for d in ds if d['meanPairwiseIDJaccard'] is not None),'sameRolePages':sum(d['sameRole'] for d in ds),'samePriorityPages':sum(d['samePriority'] for d in ds)})
global_rows=[]
for temp in manifest['temperatures']:
 for deck in manifest['pages']:
  initial=read(OUT/f't{temp:g}'/deck/'direction.json')
  directions=[{'seed':42,'direction':initial}]
  for seed in [43,44]:
   saved=read(OUT/'repeats'/f't{temp:g}'/f'seed-{seed}'/deck/'direction-repeat-response.json')
   try:
    if 'error' in saved:raise ValueError(saved['error'])
    if saved['response'].get('done_reason')=='length':raise ValueError('truncated')
    direction=json.loads(saved['response']['response'])
    count=len(read(OUT/f't{temp:g}'/deck/'slides.json'))
    ids=direction['focusPages']+direction['supportingPages']
    assert 1<=len(direction['focusPages'])<=max(1,count//3)
    assert len(direction['supportingPages'])<=max(1,count//2)
    assert len(ids)==len(set(ids)) and all(1<=i<=count for i in ids)
    directions.append({'seed':seed,'direction':direction})
   except Exception as e:directions.append({'seed':seed,'error':str(e)})
  sets=[set(d['direction']['focusPages']) for d in directions if 'direction' in d]
  j=[len(a&b)/len(a|b) for a,b in itertools.combinations(sets,2)]
  global_rows.append({'temperature':temp,'deck':deck,'directions':directions,'focusSetJaccard':statistics.mean(j) if j else None,'sameFocusSet':len(sets)==3 and all(a==sets[0] for a in sets)})
(OUT/'repeats/summary.json').write_text(json.dumps({'aggregate':aggregate,'pages':rows,'global':global_rows},ensure_ascii=False,indent=2))
lines=['# 重要ページの再実行','',
 '初回比較で選んだ2条件を、WNの5・7・9・12ページと研究資料の12・14・19・22ページで追加2回実行した。初回seed42を含め各ページ3回。全体の重点判定は各temperatureの初回結果を固定している。全体判定からの全資料再実行ではなく、ページ選択のばらつきの確認。','',
 '|Temperature|重要事項の保持|選択IDの平均一致度|役割が同じ|重要度が同じ|失敗|','|---|---:|---:|---:|---:|---:|']
for a in aggregate:lines.append(f'|{a["temperature"]:g}|{a["coveredChecks"]}/{a["totalChecks"]}|{a["meanPairwiseIDJaccard"]:.2f}|{a["sameRolePages"]}/8頁|{a["samePriorityPages"]}/8頁|{a["errors"]}/{a["attempts"]}|')
lines+=['','保持チェックは条件補完後の要約（core+detail）に対して計測し、総時間による詳細の取捨選択は再実行していない。初回の30項目表とは対象・段階が異なるため、分母や点数を直接比較しない。','',
 '一致度は3回の各ペアの選択ID集合のJaccard係数の平均。1が完全一致、0が共通IDなし。正しさそのものを表す値ではない。']
for d in rows:
 lines+=['',f'## {d["deck"]} {d["page"]}ページ / {d["temperature"]:g}','']
 for r in d['runs']:
  if 'error' in r:lines.append(f'seed {r["seed"]}: {r["error"]}');continue
  s=r['selection'];missing=[c['label'] for c in r['checks'] if not c['retained']]
  lines.append(f'- seed {r["seed"]}: {s["role"]}, 重要度{s["priority"]}, core={s["coreIDs"]}, detail={s["detailIDs"]}。未達={missing}')
lines += ['', '## 全体の重点判定を別途再実行', '', 'ページ選択の実験とは分けて、全体の重点判定もseed43・44で新規生成した。この判定を使った全ページの再生成はしていない。', '']
for g in global_rows:
 lines += [f'### {g["temperature"]:g} / {g["deck"]}', '']
 for d in g['directions']:lines.append(f'- seed {d["seed"]}: {d.get("direction",d.get("error"))}')
 lines += [f'重点ページ集合の一致度：{g["focusSetJaccard"]}。3回一致：{g["sameFocusSet"]}。', '']
(OUT/'repeats/comparison.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({"aggregate":aggregate,"global":global_rows},ensure_ascii=False,indent=2))
