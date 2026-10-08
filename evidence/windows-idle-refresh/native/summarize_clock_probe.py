#!/usr/bin/env python3
"""Summarize already-completed real-clock GTK data; never contacts application."""
import datetime, hashlib, json, pathlib
OUT=pathlib.Path(__file__).resolve().parent
RUN=sorted(OUT.glob('run-clock-*'))[-1]
def read(p):return [json.loads(s) for s in p.read_text().splitlines()]
def dt(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
a=read(RUN/'orchestrator.jsonl'); app=read(RUN/'app-trace.jsonl')
plan=next(r for r in a if r['phase']=='clockBoundaryPlan')
restore=next(r for r in a if r['phase']=='restoreAction')
unchanged=next(r for r in a if r['phase']=='canonicalUnchangedDuringObservation')
stream=next((RUN/'shared').glob('*.jsonl')); events=read(stream)
assert len(events)==4 and [e['type'] for e in events]==['user.created','task.created','task.created','task.created']
assert unchanged['sha256']==hashlib.sha256(stream.read_bytes()).hexdigest()
first,second=dt(plan['first']),dt(plan['second']); restore_t=dt(restore['utc'])
cases=[]
for name,event,begin in [('visibleUnfocused',events[2],first),('minimizedRestored',events[3],restore_t)]:
 timings={}
 for phase in ['onView','viewPublished','build','paint']:
  found=[r for r in app if r['phase']==phase and dt(r['utc'])>=begin]
  if phase=='onView':found=[r for r in found if r['openCount']==(2 if name=='visibleUnfocused' else 3)]
  if phase in ['viewPublished','build'] and 'onView' in timings:found=[r for r in found if dt(r['utc'])>=dt(timings['onView']['utc'])]
  if phase=='paint':found=[r for r in found if r['entityMarker'].split(':')[0]==event['entity']]
  assert found, (name,phase)
  r=found[0];timings[phase]={'utc':r['utc'],'msSinceBoundary' if name=='visibleUnfocused' else 'msSinceRestore':round((dt(r['utc'])-begin).total_seconds()*1000,3),'lifecycle':r['lifecycle'],'framesEnabled':r['framesEnabled']}
 cases.append({'case':name,'entity':event['entity'],'startSchedule':event['data']['schedule'],'timings':timings})
minimized=next(r for r in a if r['phase']=='clockObservationBegin' and r['case']=='minimized')
hidden=[r for r in app if dt(minimized['utc'])<=dt(r['utc'])<restore_t]
report={'baseCommit':'0a16a88355823d74c98246ed55f1ce85e45428ab','runtime':'Actual Linux GTK debug,1400x900 virtual X display:195, app1100x740,dark,xfwm4','run':RUN.name,'sourceBinding':'instrumentation-manifest.json binds the existing compiled bundle and instrumentation.patch; all bundle hashes reverified before observation','noRebuildOrProductionEdits':True,'widgetsTester':False,'forcedFrameOrTimerInput':False,'noSystemClockChangesOrSuspend':True,'canonicalSha256Unchanged':unchanged['sha256'],'cases':cases,'hiddenInterval':{'from':minimized['utc'],'through':restore['utc'],'crossedBoundary':plan['second'],'importViewBuildPaintEvents':sum(r['phase'] in ['storeRefreshBegin','onView','viewPublished','build','paint'] for r in hidden)},'outcome':'No stale-view reproduction: normal real start-time crossing published/built/painted while visible-unfocused; hidden view/import stopped and normal restore displayed second now-available task before mouseover.','limits':['Linux GTK debug on virtual X11, not Windows or release acceptance','Finite minutes, not overnight','No physical monitor power, display sleep/wake, manual display off, system suspend or remote provider observation','Parent-reported Windows High performance AC Never sleep/hibernate/display settings are context only; no automatic-sleep assumption','Observer synchronous metadata I/O may perturb diagnostic timing; not a performance benchmark'],'artifactSha256':{str(p.relative_to(OUT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(RUN.rglob('*')) if p.is_file() and not any(x in ['profile','cache','config'] for x in p.relative_to(RUN).parts)}}
(OUT/'clock-result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'outcome':report['outcome'],'cases':cases,'hiddenInterval':report['hiddenInterval']},indent=2))
