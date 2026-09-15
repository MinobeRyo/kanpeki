"""Record read-only host memory and Ollama residency for a local benchmark."""
import json,subprocess,urllib.request,datetime,sys
from pathlib import Path
result={'timestamp':datetime.datetime.now(datetime.timezone.utc).isoformat()}
for key,cmd in {'physicalMemory':['sysctl','-n','hw.memsize'],'swap':['sysctl','vm.swapusage'],'virtualMemory':['vm_stat'],'memoryPressure':['memory_pressure','-Q']}.items():
 try:
  r=subprocess.run(cmd,capture_output=True,text=True,timeout=10)
  result[key]={'returncode':r.returncode,'output':r.stdout.strip(),'error':r.stderr.strip()}
 except (OSError,subprocess.TimeoutExpired) as e:result[key]={'error':str(e)}
try:
 with urllib.request.urlopen('http://127.0.0.1:11434/api/ps',timeout=10) as response:result['ollama']=json.load(response)
except Exception as e:result['ollamaError']=str(e)
Path(sys.argv[1]).write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps({k:v for k,v in result.items() if k!='virtualMemory'},ensure_ascii=False))
