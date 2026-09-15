"""Finish one already-authorized model download and its bounded local evaluation.
No scheduler, recurring task, system settings changes or external notifications.
"""
from pathlib import Path
import datetime,json,re,subprocess,time,urllib.request,sys
ROOT=Path(__file__).resolve().parents[1]
MODEL='hf.co/unsloth/Qwen3.8-27B-GGUF:UD-Q2_K_XL'
OUT=ROOT/'evaluation/qwen38-validation';OUT.mkdir(exist_ok=True)
PYTHON=sys.executable
started=time.monotonic()
state={'model':MODEL,'status':'waiting_for_download','startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'phases':[]}
def save(status,detail):
 state.update(status=status,detail=detail,updatedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
 (OUT/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
 (OUT/'status.md').write_text('# Qwen 3.8 ローカル検証\n\n'+detail+'\n\n状態: '+status+'\n\nモデル: `'+MODEL+'`\n\n更新: '+state['updatedAt']+'\n\n結果を取得するまでは起動・速度・精度を確認済みとは扱わない。\n')
 print(status,detail,flush=True)
def api(path,data=None,timeout=20):
 req=urllib.request.Request('http://127.0.0.1:11434/api/'+path,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=timeout) as response:return json.load(response)
def run(args,timeout=1200):
 process=subprocess.run([PYTHON,*args],cwd=ROOT,capture_output=True,text=True,timeout=timeout)
 label=Path(args[0]).stem+'-'+str(len(state['phases']))
 (OUT/(label+'.log')).write_text(process.stdout+'\n'+process.stderr)
 state['phases'].append({'command':args,'returncode':process.returncode,'log':label+'.log'})
 if process.returncode:raise RuntimeError(f'{args[0]} failed: '+(process.stderr or process.stdout)[-1800:])
def snapshot(name):
 path=OUT/(name+'.json');run(['scripts/model_host_snapshot.py',str(path)],timeout=30);return json.loads(path.read_text())
def swap_mb(snapshot):
 match=re.search(r'used\s*=\s*([0-9.]+)M',snapshot.get('swap',{}).get('output',''))
 return float(match.group(1)) if match else None
attempted=False
try:
 save('waiting_for_download','モデルの取得待ちです。完了後、起動・メモリ・資料の処理を検証します。')
 failures=0
 while time.monotonic()-started < 6*3600:
  try:
   tags=api('tags');failures=0
  except Exception:
   failures+=1
   if failures>=5:raise RuntimeError('ローカルOllamaへ連続5回接続できません。')
   time.sleep(30);continue
  model=next((m for m in tags.get('models',[]) if m.get('name','').lower()==MODEL.lower()),None)
  if model:
   (OUT/'model-installed.json').write_text(json.dumps(model,ensure_ascii=False,indent=2));break
  process=subprocess.run(['pgrep','-f','^ollama pull hf.co/unsloth/Qwen3.8-27B-GGUF:UD-Q2_K_XL$'],capture_output=True,text=True)
  if process.returncode:raise RuntimeError('ダウンロード処理が終了しましたが、モデルが登録されていません。ダウンロードログの確認が必要です。')
  time.sleep(30)
 else:raise RuntimeError('6時間以内にダウンロードが完了しませんでした。モデルの評価は未実施です。')
 save('smoke_test','ダウンロード完了。研究資料19ページで起動と実行速度を確認中です。')
 before=snapshot('host-before-load');attempted=True
 run(['scripts/evaluate_deck.py','run','--out','evaluation/qwen38-research','--pages','19'],timeout=360)
 after=snapshot('host-after-smoke')
 record=json.loads((ROOT/'evaluation/qwen38-research/page-19.json').read_text())
 selection=json.loads(record['response']['response']);ids=selection['coreIDs']+selection['detailIDs']
 if not selection['coreIDs'] or not all(i in {p['id'] for p in record['points']} for i in ids):raise RuntimeError('起動テストの選択IDが不正です。')
 if record['response'].get('done_reason')=='length':raise RuntimeError('起動テストの生成がトークン上限で途切れました。')
 delta=swap_mb(after)-swap_mb(before) if swap_mb(after) is not None and swap_mb(before) is not None else None
 state['smokeTest']={'page':19,'elapsedSeconds':record['elapsedSeconds'],'swapIncreaseMB':delta}
 if record['elapsedSeconds']>90 or (delta is not None and delta>2048):
  save('limited_by_resources',f'モデルは起動しましたが、1ページ {record["elapsedSeconds"]:.1f}秒、スワップ増加 {delta} MBでした。負荷を抑えるため全資料の比較を中止しました。他のアプリの影響も含む測定です。')
 else:
  save('research_evaluation','起動テストを通過。前回と同じ25ページ・600秒の比較を実行中です。')
  run(['scripts/evaluate_deck.py','run','--out','evaluation/qwen38-research','--resume'])
  run(['scripts/evaluate_deck.py','assemble','--out','evaluation/qwen38-research','--budget','600'])
  run(['scripts/compare_model_runs.py','--baseline','evaluation/second-deck','--candidate','evaluation/qwen38-research','--output','evaluation/qwen38-validation/research-comparison.md'])
  middle=snapshot('host-after-research')
  delta2=swap_mb(middle)-swap_mb(before) if swap_mb(middle) is not None and swap_mb(before) is not None else None
  if delta2 is not None and delta2>2048:
   save('research_completed_resource_limit','25ページの比較結果を保存しました。スワップ使用量が2GB以上増えたため追加資料の処理は止めました。内容の意味の評価には比較表の確認が必要です。')
  else:
   save('wn_evaluation','研究資料の比較を保存しました。前回のWN資料15ページでも実行中です。')
   run(['scripts/evaluate_deck.py','run','--out','evaluation/qwen38-wn','--resume'])
   run(['scripts/evaluate_deck.py','assemble','--out','evaluation/qwen38-wn','--budget','600'])
   snapshot('host-after-both-decks')
   save('execution_completed','ダウンロード・起動・2資料40ページの処理と配分が完了しました。研究資料の比較表を保存しました。語句保持の自動チェックは意味の正しさを保証しないため、内容品質の最終判定は未実施です。')
except Exception as error:
 save('blocked',str(error))
finally:
 if attempted:
  try:
   api('generate',{'model':MODEL,'keep_alive':0},timeout=30)
   state['modelUnloadedAfterTest']=True
  except Exception as error:state['unloadError']=str(error)
  (OUT/'status.json').write_text(json.dumps(state,ensure_ascii=False,indent=2))
