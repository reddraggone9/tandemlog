"""Bounded isolated-process malformed native-update probe; no real data."""
import base64,json,random,resource,sys
from pathlib import Path
resource.setrlimit(resource.RLIMIT_AS,(512*1024*1024,512*1024*1024))
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
resource.setrlimit(resource.RLIMIT_CPU,(10,10))
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tests'))
from test_contract import Bridge
b=Bridge();b.ok('reset');b.ok('new',name='a',client=10,seed=b.ok('seed',text='safe')['update'])
rng=random.Random(742)
samples=[b'\x01'+b'\xff'*12,b'\x00\x01'+b'\xff'*12,b'\x01\x01\x01\x00\x84'+b'\xff'*12]
samples += [rng.randbytes(rng.randrange(1,80)) for _ in range(1000)]
errors=accepted=0
for raw in samples:
    before=b.ok('state',name='a')['update']
    r=b.request(op='apply',name='a',update=base64.b64encode(raw).decode())
    if 'error' in r:
        errors+=1
        assert b.ok('state',name='a')['update']==before
    else:accepted+=1
print(json.dumps({'samples':len(samples),'rejected_without_state_change':errors,'accepted':accepted,'native_process_survived':True,'scope':'bounded sample, not a security proof'}))
