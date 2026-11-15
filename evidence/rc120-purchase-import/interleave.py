# Diagnostic only: existing instrumented binaries, no acceptance/retry receipts.
import json, os, pathlib, subprocess
root=pathlib.Path(__file__).resolve().parent
fixture_root=pathlib.Path('/home/lee/aux/vex-private/tandemlog-next-20261114/reference/q23/failed-invocation/run')
env=dict(os.environ, TANDEMLOG_TEXT_LIBRARY='/home/lee/.cache/tandemlog-rc119-focus-rust/x86_64-unknown-linux-gnu/release/libtandemlog_text.so', LD_PRELOAD=str(pathlib.Path('.dart_tool/lib/libsqlite3.so').resolve()))
for shape in ['dense-1','dense-food']:
    path=fixture_root/f'fixture-{shape}'/'fixture.json'
    value=json.loads(path.read_text());value['workspace']=str(path.parent/'workspace')
    manifest=pathlib.Path(f'/tmp/rc120-ab-{shape}.json');manifest.write_text(json.dumps(value))
    for round in range(4):
        for variant in (['before','after'] if round%2==0 else ['after','before']):
            exe='/tmp/rc120-key' if variant=='before' else '/tmp/rc120-fixed'
            output=f'/tmp/rc120-ab-{shape}-{round}-{variant}'
            with (root/f'ab-{shape}-{round}-{variant}.log').open('w') as log:
                subprocess.run(['taskset','-c','0,1',exe,output,str(manifest)],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
