"""Repeat eight fixed diagnostic pages; hold each setting's first-pass global direction fixed."""
import argparse,json,random,time
from pathlib import Path
from benchmark_temperature import OUT,ROOT,read,write,generate,helper
p=argparse.ArgumentParser();p.add_argument('--temperatures',type=float,nargs='+',required=True);a=p.parse_args()
PAGES={'wn':[5,7,9,12],'research':[12,14,19,22]}
manifest={'temperatures':a.temperatures,'seeds':[43,44],'pages':PAGES,'scope':'Global directions repeat separately. Diagnostic page selections hold initial full-run global directions fixed per temperature. This is not a repeated full-deck pipeline.'}
write(OUT/'repeats/manifest.json',manifest)
jobs=[]
for temp in a.temperatures:
 for seed in [43,44]:
  for deck,indices in PAGES.items():
   base=OUT/f't{temp:g}'/deck;folder=OUT/'repeats'/f't{temp:g}'/f'seed-{seed}'/deck
   for filename in ['slides.json','direction.json']:write(folder/filename,read(base/filename))
   requests=read(base/'requests.json')
   for q in requests:q['request']['options']['seed']=seed
   write(folder/'requests.json',requests)
   for q in requests:
    if q['slideIndex'] in indices:jobs.append((temp,seed,deck,folder,q))
random.Random(20260911).shuffle(jobs)
for temp,seed,deck,folder,q in jobs:
 result=generate(q['request'],folder/f'page-{q["slideIndex"]:02d}.json')
 result.update({k:v for k,v in q.items() if k!='request'})
 write(folder/f'page-{q["slideIndex"]:02d}.json',result)
 print(f'{deck} p{q["slideIndex"]} temperature={temp:g} seed={seed} {result["elapsedSeconds"]:.1f}s '+result.get('error','ok'),flush=True)
for deck in PAGES:
 for temp in a.temperatures:
  for seed in [43,44]:
   base=OUT/f't{temp:g}'/deck
   req=read(base/'direction-request.json');req['options']['seed']=seed
   folder=OUT/'repeats'/f't{temp:g}'/f'seed-{seed}'/deck
   result=generate(req,folder/'direction-repeat-response.json')
   print(f'GLOBAL REPEAT {deck} temperature={temp:g} seed={seed} {result["elapsedSeconds"]:.1f}s',flush=True)
   folder=OUT/'repeats'/f't{temp:g}'/f'seed-{seed}'/deck
   records=[read(p) for p in sorted(folder.glob('page-[0-9][0-9].json'))]
   write(folder/'records.json',[r for r in records if 'response' in r])
   helper('assemble',folder,deck,temp)
print('REPEATS COMPLETE',flush=True)
