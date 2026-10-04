"""Implements prewritten P01/P02 measurement gates, not app startup claims."""
import ctypes,json,os,resource,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests'))
from test_contract import Bridge

if '--fresh' in sys.argv:
    start=time.perf_counter();b=Bridge();loaded=time.perf_counter()
    b.ok('reset');s=b.ok('seed',text='Synthetic notes')['update'];b.ok('new',name='a',client=10,seed=s)
    ready=time.perf_counter()
    print(json.dumps({'load_ms':(loaded-start)*1000,'first_document_ms':(ready-loaded)*1000}))
    raise SystemExit

fresh=[json.loads(subprocess.check_output([sys.executable,__file__,'--fresh'])) for _ in range(5)]
b=Bridge();b.ok('reset');base=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
seed=b.ok('seed',text='Synthetic notes '*4)['update'];start=time.perf_counter()
for i in range(2000):b.ok('new',name=f'field{i}',client=100+i,seed=seed)
fields_ms=(time.perf_counter()-start)*1000
peak=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
b.ok('new',name='churn',client=5000,seed=b.ok('seed',text='x')['update'])
start=time.perf_counter()
for i in range(2500):
    b.ok('edit',name='churn',index=0,delete=1,insert='y' if i%2==0 else 'x')
churn_ms=(time.perf_counter()-start)*1000
checkpoint=b.ok('checkpoint',name='churn')['checkpoint']
restored=b.request(op='restore',name='churn-restored',client=6000,checkpoint=checkpoint)
report={'method':'Linux release SO; Python ctypes wall times; fresh processes, OS page caches not flushed; in-memory engine/JSON, not disk/SQLite/Flutter first frame','fresh_process_samples':fresh,'fields':2000,'fields_create_and_ffi_ms':fields_ms,'peak_rss_before_kib':base,'peak_rss_after_fields_kib':peak,'replacement_edits':2500,'replacement_edit_and_ffi_ms':churn_ms,'checkpoint_json_bytes':len(json.dumps(checkpoint).encode()),'restore_result':restored}
print(json.dumps(report,indent=2))
