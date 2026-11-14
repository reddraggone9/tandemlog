import re,json,sys,statistics as st
from pathlib import Path
base=Path("/home/nibbler/tandemlog-stalls-lab/runs")
prefix=sys.argv[1]; n=int(sys.argv[2])
out={}
for side in ("before","after"):
    for i in range(1,n+1):
        for line in (base/f"{prefix}-{side}-{i}/result.txt").read_text().splitlines():
            m=re.match(r"(strict|warm) process_ms (\d+) app_ms (\d+) stall (\d+) (\[.*\]) (\{.*\})",line)
            if not m: continue
            mode=m.group(1); stalls=json.loads(m.group(5)); ph=json.loads(m.group(6))
            out.setdefault((mode,side),[]).append(dict(proc=int(m.group(2)),app=int(m.group(3)),max=int(m.group(4)),stalls=stalls,ph=ph))
for k,v in sorted(out.items()):
    app=[r["app"] for r in v]; mx=[r["max"] for r in v]; proc=[r["proc"] for r in v]
    over=[sum(1 for s in r["stalls"] if s[1]>16) for r in v]
    over_t=[sum(s[1] for s in r["stalls"] if s[1]>16) for r in v]
    # excluding entry gap (start<5)
    mx2=[max([s[1] for s in r["stalls"] if s[0]>=5] or [0]) for r in v]
    print(k,"n",len(v),"app med",st.median(app),sorted(app),"proc med",st.median(proc),"max med",st.median(mx),sorted(mx),"max-excl-entry",sorted(mx2),"n>16.7",over,"sum>16",over_t)
    print("   phases med",{p:st.median([r["ph"][p] for r in v]) for p in v[0]["ph"]})
for mode in ("strict","warm"):
    d=[a["app"]-b["app"] for a,b in zip(out[(mode,"after")],out[(mode,"before")])]
    print(mode,"paired app diff after-before",d,"median",st.median(d),"mean",round(st.mean(d),1))
    d=[a["proc"]-b["proc"] for a,b in zip(out[(mode,"after")],out[(mode,"before")])]
    print(mode,"paired process diff",d,"median",st.median(d))
for mode in ("strict","warm"):
  for r in out[(mode,"after")]:
    print(mode,"after >16:",[s for s in r["stalls"] if s[1]>16],"list@",r["app"],r["ph"]["history"],r["ph"]["bound"])
