#!/usr/bin/env python3
"""Synthetic canonical peer + normal GTK process; no Flutter test pump/input loop."""
import datetime, hashlib, json, os, pathlib, subprocess, time, uuid
ROOT = pathlib.Path(__file__).resolve().parents[3]
OUT = pathlib.Path(__file__).resolve().parent
RUN = OUT / 'run-04'
RUN.mkdir(exist_ok=True)
SHARED = RUN / 'shared'; SHARED.mkdir(exist_ok=True)
PROFILE = RUN / 'profile'; PROFILE.mkdir(exist_ok=True)
trace = RUN / 'orchestrator.jsonl'
def record(phase, **values):
    row = {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'phase': phase, **values}
    with trace.open('a') as f: f.write(json.dumps(row, sort_keys=True) + '\n')
    print(json.dumps(row), flush=True)
def canonical(data): return json.dumps(data, ensure_ascii=False, separators=(',', ':'))
space, writer, user = (str(uuid.uuid4()) for _ in range(3))
appwriter = str(uuid.uuid4()); seq = 0
previous = hashlib.sha256(f'tandemlog:genesis:v3\n{space}\n{writer}\n'.encode()).hexdigest()
log = SHARED / f'{writer}.jsonl'
def append(title=None):
    global seq, previous
    seq += 1
    data = {'name': 'Synthetic idle QA'} if title is None else {'assignee': user, 'description': '', 'title': title}
    row = {'v': 3, 'space': space, 'writer': writer, 'seq': seq, 'clock': str(time.time_ns()), 'entity': user if title is None else str(uuid.uuid4()), 'type': 'user.created' if title is None else 'task.created', 'data': dict(sorted(data.items())), 'previousHash': previous}
    row['hash'] = hashlib.sha256(('tandemlog:event:v3\n' + canonical(row)).encode()).hexdigest()
    previous = row['hash']; payload = (canonical(row) + '\n').encode()
    with log.open('ab') as f: f.write(payload); f.flush(); os.fsync(f.fileno())
    actual = log.read_bytes()
    assert actual.endswith(payload)
    record('externalCanonicalArrivalVerified', title=title, seq=seq, bytes=len(actual), sha256=hashlib.sha256(actual).hexdigest(), path=str(log), eventHash=row['hash'])
(SHARED / 'tandemlog-space.json').write_text(canonical({'v': 3, 'space': space}))
# Manifest uses id, not event envelope space.
(SHARED / 'tandemlog-space.json').write_text(canonical({'v': 3, 'id': space}))
(PROFILE / 'settings.json').write_text(canonical({'folder': str(SHARED), 'user': user, 'appearance': 'dark', 'writer': appwriter}))
(PROFILE / 'writer-migration.json').write_text('{"v":1}')
append(); append('Baseline synthetic task')
(OUT / 'fixture.json').write_text(json.dumps({'space': space, 'peerWriter': writer, 'appWriter': appwriter, 'user': user, 'profile': str(PROFILE), 'shared': str(SHARED)}, indent=2)+'\n')
env = dict(os.environ, TANDEMLOG_IDLE_PROBE='synthetic-only', DISPLAY=':194', TANDEMLOG_PROFILE=str(PROFILE), TANDEMLOG_IDLE_TRACE=str(RUN / 'app-trace.jsonl'), XDG_CACHE_HOME=str(RUN / 'cache'), XDG_CONFIG_HOME=str(RUN / 'config'))
processes=[]
def spawn(args, name):
    f=(RUN / name).open('w'); p=subprocess.Popen(args, env=env, stdout=f, stderr=subprocess.STDOUT); processes.append((p,f)); return p
def command(*args):
    r=subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=15)
    return r.stdout.strip()
def pause(seconds):
    until=time.monotonic()+seconds
    while time.monotonic()<until: time.sleep(min(1,until-time.monotonic()))
def screen(name):
    command('/usr/bin/import', '-window', 'root', str(RUN / f'{name}.png'))
    p=RUN / f'{name}.png'; record('screenshot', name=name, sha256=hashlib.sha256(p.read_bytes()).hexdigest(), pointer=command('xdotool','getmouselocation','--shell'))
def state(label):
    record('windowState', label=label, active=command('xdotool','getactivewindow'), app=app_id, details=command('xprop','-id',app_id,'WM_STATE','_NET_WM_STATE'))
try:
    spawn(['Xvfb', ':194', '-screen', '0', '1400x900x24', '-nolisten', 'tcp'], 'xvfb.txt'); pause(2)
    spawn(['/usr/bin/xfwm4','--replace','--compositor=off'], 'wm.txt'); pause(2)
    command('xdotool','mousemove','1390','890')
    app=spawn([str(ROOT / 'build/linux/x64/debug/bundle/tandemlog')], 'app-stdout.txt')
    app_id=''
    for _ in range(40):
        result=subprocess.run(['xdotool','search','--onlyvisible','--pid',str(app.pid)],env=env,text=True,stdout=subprocess.PIPE)
        if result.stdout.strip(): app_id=result.stdout.splitlines()[-1]; break
        pause(0.5)
    if not app_id: raise RuntimeError('GTK app window absent')
    command('xdotool','windowmove',app_id,'20','20'); command('xdotool','windowsize',app_id,'1100','740'); command('xdotool','windowactivate','--sync',app_id)
    pause(10); state('focusedReady'); screen('01-baseline-focused')
    record('idleBegin', case='focused', seconds=25, noInput=True); append('Focused idle arrival')
    pause(25); screen('02-focused-arrived-before-input'); state('focusedComplete')
    dummy=spawn(['/usr/bin/xmessage','-name','idle-focus-target','-geometry','240x70+1140+780','Independent focus target'], 'dummy.txt'); pause(2)
    dummy_id=command('xdotool','search','--onlyvisible','--name','idle-focus-target').splitlines()[-1]
    command('xdotool','windowactivate','--sync',dummy_id); pause(5); state('visibleUnfocusedReady'); screen('03-visible-unfocused-before')
    record('idleBegin', case='visibleUnfocused', seconds=70, noInput=True); append('Visible unfocused arrival')
    pause(70); screen('04-visible-unfocused-arrived-before-input'); state('visibleUnfocusedComplete')
    record('minimizeAction'); command('xdotool','windowminimize',app_id); pause(5); state('minimizedReady'); screen('05-minimized-before')
    record('idleBegin', case='minimized', seconds=35, noInput=True); append('Minimized external arrival')
    pause(35); screen('06-minimized-after-arrival'); state('minimizedComplete')
    record('restoreAction', mouseover=False); command('xdotool','windowmap',app_id); command('xdotool','windowactivate','--sync',app_id)
    pause(15); screen('07-restored-arrival-before-mouseover'); state('restoredComplete')
    record('probeComplete', appExit=app.poll())
finally:
    for p,f in reversed(processes):
        if p.poll() is None: p.terminate()
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill();p.wait()
        f.close()
