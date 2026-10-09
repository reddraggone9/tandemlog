"""Native Linux startup: process launch to loaded-frame marker.
Synthetic data only. Does not flush OS page caches or claim device cold boot.
Run from repo with its native Linux release binary built and DISPLAY configured.
"""
import json, os, pathlib, subprocess, time, uuid, hashlib, selectors, argparse, sqlite3
from contextlib import closing
parser=argparse.ArgumentParser()
parser.add_argument('--tasks', type=int, default=2000)
parser.add_argument('--runs', type=int, default=5)
parser.add_argument('--binary', default='build/linux/x64/release/bundle/tandemlog')
parser.add_argument('--label', default='tasks')
parser.add_argument('--workspace', default='/workspace/tandemlog-performance', help='Dedicated disposable benchmark directory; never use a real profile')
args=parser.parse_args()
if args.tasks < 0 or args.runs < 1:parser.error('tasks must be nonnegative and runs must be positive')
root=pathlib.Path(args.workspace)
root.mkdir(exist_ok=True)
folder=root/'shared';folder.mkdir(exist_ok=True)
profile=root/'profile';profile.mkdir(exist_ok=True)
if any(profile.iterdir()) or any(folder.iterdir()):
 raise RuntimeError('Benchmark requires fresh empty profile/shared directories; existing state retained')
space,writer,user=(str(uuid.uuid4()) for _ in range(3))
(folder/'tandemlog-space.json').write_text(json.dumps({'v':3,'id':space}))
events=[]
batch_ns=time.time_ns()
previous=hashlib.sha256(f'tandemlog:genesis:v3\n{space}\n{writer}\n'.encode()).hexdigest()
for n in range(args.tasks+1):
 entity=user if n==0 else str(uuid.uuid4())
 data={'name':'Benchmark user'} if n==0 else {'title':f'Task {n:04d}','description':'Synthetic startup workload','assignee':user}
 # Protocol-v3 envelope order is fixed; this synthetic payload contains only
 # ASCII strings and one object whose keys use canonical scalar ordering.
 record={'v':3,'space':space,'writer':writer,'seq':n+1,'clock':str(batch_ns+n),'entity':entity,'type':'user.created' if n==0 else 'task.created','data':dict(sorted(data.items())),'previousHash':previous}
 unsigned=json.dumps(record,ensure_ascii=False,separators=(',',':'))
 record['hash']=hashlib.sha256(('tandemlog:event:v3\n'+unsigned).encode()).hexdigest()
 previous=record['hash']
 events.append(json.dumps(record,ensure_ascii=False,separators=(',',':')))
(folder/f'{writer}.jsonl').write_text('\n'.join(events)+'\n')
(profile/'settings.json').write_text(json.dumps({'folder':str(folder),'user':user}))
key=hashlib.sha256(str(folder).encode()).hexdigest()
cache=profile/'spaces'/key
results=[]
for i in range(args.runs):
 env=dict(os.environ,TANDEMLOG_PROFILE=str(profile),GSETTINGS_BACKEND='memory')
 start=time.perf_counter()
 proc=subprocess.Popen([args.binary],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
 sel=selectors.DefaultSelector();sel.register(proc.stdout,selectors.EVENT_READ)
 output=b'';marker=None;marks={};lines=[];pending=b''
 while time.perf_counter()-start<45:
  if sel.select(timeout=.1):
   chunk=os.read(proc.stdout.fileno(),65536)
   if not chunk and proc.poll() is not None:break
   output+=chunk;pending+=chunk
   while b'\n' in pending:
    raw,pending=pending.split(b'\n',1)
    line=raw.decode(errors='replace').strip()
    if line.startswith('TANDEMLOG_'):
     lines.append(line)
     if line=='TANDEMLOG_MAIN':marks['external_main_ms']=round((time.perf_counter()-start)*1000)
     if line.startswith('TANDEMLOG_FIRST_FRAME_MS='):marks['external_first_frame_ms']=round((time.perf_counter()-start)*1000)
    if 'TANDEMLOG_READY_MS=' in line:marker=line
   if marker:break
 elapsed=round((time.perf_counter()-start)*1000)
 proc.terminate()
 try:proc.wait(timeout=5)
 except subprocess.TimeoutExpired:proc.kill();proc.wait()
 if not marker:raise RuntimeError('No loaded-frame marker: '+output.decode(errors='replace'))
 if not args.label.startswith('minimal'):
  if not any(line.startswith('TANDEMLOG_ROWS ') for line in lines):
   raise RuntimeError('Ready marker was emitted without a successful model load')
  database=profile/'local.sqlite' if (profile/'local.sqlite').exists() else cache/'cache.sqlite'
  table=f'tasks_{key}_views' if database.name=='local.sqlite' else 'views'
  with closing(sqlite3.connect(str(database),timeout=0)) as db:
   db.execute('PRAGMA locking_mode=EXCLUSIVE')
   projected=[json.loads(row[0]) for row in db.execute(f'SELECT raw FROM {table}')]
  if len(projected)!=args.tasks+1 or sum(row['kind']=='task' for row in projected)!=args.tasks:
   raise RuntimeError('Loaded cache does not contain the complete synthetic workload')
  if i>0 and not marker.endswith('FILES_READ=0'):
   raise RuntimeError('Warm cache unexpectedly replayed canonical log contents')
 results.append({'run':i+1,'cache':('not used' if args.label.startswith('minimal') else ('rebuild' if i==0 else 'warm')),'external_ms':elapsed,'marker':marker,'phases':lines,**marks})
print(json.dumps({'target':'Linux x86_64 native / Xvfb','binary':args.binary,'tasks':args.tasks,'label':args.label,'os_page_cache':'not flushed','results':results},indent=2))
