import sys,os,re,json,urllib.request,runpy
from pathlib import Path
b=Path('/home/nibbler/tandemlog-stalls-lab')
sys.path[:0]=['/home/nibbler/tandemlog-startup-20261113/repo/tool']
import measure_startup as m
orig=m.finish_process
count=0
def finish(*args):
 global count
 count+=1
 root=Path(sys.argv[3]);diag=root/'diagnostics'
 log=(diag/f'run-{count}.stdout-stderr.log').read_text()
 match=re.search(r'listening on (http://\S+)',log)
 if match:
  url=match.group(1)
  def get(method):return urllib.request.urlopen(url+method).read()
  vm=json.loads(get('getVM'))['result']; iso=vm['isolates'][0]['id']
  for name,method in [('timeline','getVMTimeline'),('cpu','getCpuSamples?isolateId='+iso+'&timeOriginMicros=0&timeExtentMicros=999999999999999')]:
   (b/f'pass5-{count}-{name}.json').write_bytes(get(method))
 else: print('NO VM URL',flush=True)
 return orig(*args)
m.finish_process=finish
os.environ.update(FLUTTER_ENGINE_SWITCHES='2',FLUTTER_ENGINE_SWITCH_1='enable-dart-profiling=true',FLUTTER_ENGINE_SWITCH_2='trace-startup=true')
runpy.run_path(str(b/'stallrun.py'),run_name='__main__')
