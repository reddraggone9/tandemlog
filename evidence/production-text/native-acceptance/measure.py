import ctypes,json,time,resource,sys,hashlib,subprocess,base64,os
from pathlib import Path
SO='/tmp/tandemlog-production-text-libs/linux/libtandemlog_text.so'
def rss():
 return int(next(x.split()[1] for x in Path('/proc/self/status').read_text().splitlines() if x.startswith('VmRSS:')))
def var(n):
 o=bytearray()
 while n>127:o.append((n&127)|128);n>>=7
 o.append(n);return bytes(o)
def packet(n):
 return base64.b64encode(bytes([1,1,50,0,4,1,4])+b'text'+var(n)+b'H'*n+bytes([0])).decode()
if len(sys.argv)==1:
 results=[]
 for mode in ['idle','title100','title1000','notes100','notes1000','hostile500','hostile10000']:
  try:
   p=subprocess.run([sys.executable,__file__,mode],capture_output=True,text=True,timeout=60)
   results.append({'mode':mode,'exit':p.returncode,'result':json.loads(p.stdout) if p.returncode==0 else p.stdout,'stderr':p.stderr})
  except subprocess.TimeoutExpired:results.append({'mode':mode,'timeoutSeconds':60})
 Path('/tmp/tandemlog-native-acceptance-evidence/results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2));sys.exit()
mode=sys.argv[1]; baseline=rss(); lib=ctypes.CDLL(SO);lib.tandemlog_text_json.argtypes=[ctypes.c_char_p];lib.tandemlog_text_json.restype=ctypes.c_void_p;lib.tandemlog_text_free.argtypes=[ctypes.c_void_p]
loaded=rss();times={}
def call(op,allow=False,**kw):
 raw=json.dumps(dict(op=op,**kw)).encode();t=time.perf_counter_ns();p=lib.tandemlog_text_json(raw)
 try:r=json.loads(ctypes.string_at(p))
 finally:lib.tandemlog_text_free(p)
 times.setdefault(op,[]).append((time.perf_counter_ns()-t)/1e6)
 if 'error' in r and not allow:raise RuntimeError(r)
 return r
limits=dict(visibleUtf16=500 if 'title' in mode or mode=='hostile500' else 10000,updateBytes=1048576,stateBytes=8388608,sessionBytes=16777216,retainedBytes=67108864)
if mode=='idle':
 # Native-only loaded library: no calls, no synthetic Python tasklist allocation.
 outcome={'nativeDocsCreated':0,'nativeCalls':0,'taskListRows':2000,'qualification':'models lazy native allocation; actual Dart idle-list allocation requires app integration evidence'}
else:
 seed=call('seed',text='a'*(limits['visibleUtf16']-2))['update'];call('new',name='a',client=10,seed=seed,limits=limits); initialized=rss()
 if mode.startswith('hostile'):
  # Fixed valid V1 single plaintext struct, exact 1MiB decoded packet. Oversized visible result must reject.
  n=1048561; update=packet(n);decoded=len(base64.b64decode(update));before=call('state',name='a')['update'];pre_payload_rss=rss();result=call('apply',allow=True,name='a',update=update);after=call('state',name='a')['update'];outcome={'preApplyPayloadRssKiB':pre_payload_rss,'decodedUpdateBytes':decoded,'rejection':result,'stateUnchanged':before==after}
 else:
  count=1000 if mode.endswith('1000') else 100
  call('draft',name='draft',source='a',client=30)
  for i in range(count):call('edit',name='draft',index=0,delete=1,insert='b' if i%2==0 else 'c')
  call('read',name='draft');prepared=call('prepare',name='draft',target='a')
  call('new',name='remote',client=20,seed=seed,limits=limits)
  remote=call('edit',name='remote',index=1,delete=1,insert='R')['update'];call('apply',name='a',update=remote)
  saved=call('save',name='draft',target='a');u=call('prepare_undo',name='a')
  remote2=call('edit',name='remote',index=2,delete=1,insert='S')['update'];call('apply',name='a',update=remote2)
  call('commit_undo',name='a',token=u['token'],receipt={'update':u['update']});read=call('read',name='a');outcome={'edits':count,'remotePreserved':read['text'][1:3]=='RS','preparedEqualsSaved':prepared['update']==saved['update'],'usage':call('usage',name='a')}
 outcome['initializedRssKiB']=initialized
stats={k:{'count':len(v),'maxMs':max(v),'meanMs':sum(v)/len(v),'p95Ms':sorted(v)[min(len(v)-1,int(len(v)*.95))]} for k,v in times.items()}
print(json.dumps({'mode':mode,'soSha256':hashlib.sha256(Path(SO).read_bytes()).hexdigest(),'baselineRssKiB':baseline,'loadedRssKiB':loaded,'finalRssKiB':rss(),'peakRssKiB':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,'peakMinusBaselineKiB':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss-baseline,'calls':stats,'outcome':outcome}))
