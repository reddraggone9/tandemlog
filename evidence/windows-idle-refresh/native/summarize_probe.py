#!/usr/bin/env python3
"""Read-only deterministic report from preserved successful raw GTK probe."""
import datetime, hashlib, json, pathlib, subprocess
OUT=pathlib.Path(__file__).resolve().parent
RUN=OUT/'run-04'
def load(p): return [json.loads(x) for x in p.read_text().splitlines()]
def dt(x): return datetime.datetime.fromisoformat(x.replace('Z','+00:00'))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
app=load(RUN/'app-trace.jsonl'); orchestration=load(RUN/'orchestrator.jsonl')
canonical=load(next((RUN/'shared').glob('*.jsonl')))
restore=next(x for x in orchestration if x['phase']=='restoreAction')
report={'baseCommit':'0a16a88355823d74c98246ed55f1ce85e45428ab','runtime':'actual Linux GTK debug, Xvfb1400x900, xfwm4, app1100x740, dark','widgetsTesterUsed':False,'extraFrameRequests':False,'pointerOutsideApp':'1390,890 throughout all screenshots','cases':[],'screenshotsViewed':['01-baseline-focused.png','02-focused-arrived-before-input.png','04-visible-unfocused-arrived-before-input.png','06-minimized-after-arrival.png','07-restored-arrival-before-mouseover.png'],'limits':['Not Windows reproduction or Windows acceptance','Not all-night idle, physical display sleep/wake, release build, real cloud provider or remote transport','Instrumentation adds synchronous local metadata I/O and RenderProxyBox observers; timing is diagnostic, not a performance benchmark','Initial aborted/mixed setup run-01 and display-race run-03 are excluded from acceptance']}
for arrival in (r for r in orchestration if r['phase']=='externalCanonicalArrivalVerified' and r['seq']>=3):
 event=next(r for r in canonical if r['seq']==arrival['seq'])
 t=dt(arrival['utc']); case=['focused','visibleUnfocused','minimized'][arrival['seq']-3]
 upper=dt(restore['utc']) if case=='minimized' else dt(next(r for r in orchestration if r['phase']=='idleBegin' and r['case']==case)['utc'])+datetime.timedelta(seconds=25 if case=='focused' else 70)
 begin=t if case!='minimized' else dt(restore['utc'])
 timings={}
 for phase in ['watchEvent','reconcileBegin','storeRefreshBegin','storeRefreshEnd','rowsPublished','onView','viewPublished','build','paint','postFrame']:
  candidates=[r for r in app if r['phase']==phase and dt(r['utc'])>=begin]
  if phase in ['onView','viewPublished','build'] and 'rowsPublished' in timings:
   candidates=[r for r in candidates if dt(r['utc'])>=dt(timings['rowsPublished']['utc'])]
  if phase=='rowsPublished':candidates=[r for r in candidates if event['entity'] in r['taskIds']]
  if phase=='paint':candidates=[r for r in candidates if r['entityMarker'].split(':')[0]==event['entity']]
  if phase=='storeRefreshEnd':candidates=[r for r in candidates if r['changed']]
  if candidates:
   r=candidates[0];timings[phase]={'utc':r['utc'],'msSinceVerifiedArrival' if case!='minimized' else 'msSinceRestore':round((dt(r['utc'])-begin).total_seconds()*1000,3),'lifecycle':r['lifecycle'],'framesEnabled':r['framesEnabled']}
 interval=[r for r in app if t<=dt(r['utc'])<upper]
 result={'case':case,'sequence':arrival['seq'],'entity':event['entity'],'verifiedArrivalUtc':arrival['utc'],'observationSeconds':25 if case=='focused' else 70 if case=='visibleUnfocused' else 35,'timings':timings,'fallbackTicksDuringInterval':sum(r['phase']=='fallback' for r in interval)}
 if case=='minimized':result['importBuildPaintEventsBeforeRestore']=sum(r['phase'] in ['storeRefreshBegin','rowsPublished','onView','build','paint'] for r in interval)
 report['cases'].append(result)
report['outcome']='No stale-view reproduction in this bounded actual GTK observation: foreground/inactive writes painted before input; hidden importer stopped and restore imported/painted without mouseover.'
report['artifactSha256']={str(p.relative_to(OUT)):digest(p) for p in sorted(RUN.rglob('*')) if p.is_file() and not any(part in ['profile','cache','config'] for part in p.relative_to(RUN).parts)}
(OUT/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'outcome':report['outcome'],'cases':report['cases']},indent=2))
