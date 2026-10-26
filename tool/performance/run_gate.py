#!/usr/bin/env python3
"""Compile and run public synthetic AOT benchmarks; no user-data argument exists.
The caller supplies its reviewed Dart/native/SQLite binaries and resource limits.
"""
import argparse
import hashlib
import json
import os
import platform
try:
    import resource
except ImportError:  # Policy tests also run on Windows.
    resource = None
import re
import signal
import pathlib
import subprocess
import sys
import time
import shutil
import urllib.parse
from gate_policy import evaluate, evaluate_scaling, may_rerun, Evaluation, validate_registered_coverage, may_complete_with_advisory_timing
from reference_receipt import request_context, package_contract, read as read_reference_json, utc, check_reference_toolchain, profile as reference_profile

def digest(path):
    value=hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):
            value.update(chunk)
    return value.hexdigest()

def runtime_environment():
    # Fixed non-personal fields only; never serialize the ambient environment.
    result={'architecture':platform.machine(),'kernel':platform.release(),
            'python':platform.python_version(),'logicalCPUs':os.cpu_count(),
            'runnerImage':{k:os.environ[k] for k in ('ImageOS','ImageVersion','RUNNER_OS','RUNNER_ARCH') if k in os.environ}}
    try:
        for line in pathlib.Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name') and ':' in line:
                result['cpuModel']=line.split(':',1)[1].strip();break
    except OSError:pass
    return result

def write_new(path, value):
    with pathlib.Path(path).open('x') as stream:
        json.dump(value, stream, indent=2); stream.write('\n')

def source_pins(root, tools):
    paths=[p for p in (root/'lib').rglob('*') if p.is_file()]
    paths += [root/'pubspec.yaml', root/'pubspec.lock']
    paths += [p for p in tools.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    if any(p.is_symlink() for p in paths):raise RuntimeError('Compiled source symlinks are not allowlisted')
    return {str(p.resolve()):digest(p) for p in sorted(set(paths))}

def validate_project_imports(entry, fork, package_names):
    """No source rewriting/shims. Follow all project directives, including parts.
    The owned source and tool sources must remain byte-identical to their inputs.
    """
    pending=[entry.resolve()];seen=set();lib=(fork/'lib').resolve();tools=entry.parent.resolve()
    directive=re.compile(r"(?m)^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]([^;]*);")
    while pending:
        source=pending.pop()
        if source in seen:continue
        if not source.is_file():raise RuntimeError('Missing compiled project source')
        seen.add(source)
        for match in directive.finditer(source.read_text()):
            uris=[match.group(1)]+re.findall(r"['\"]([^'\"]+)['\"]",match.group(2))
            for uri in uris:
                if uri=='dart:ui' or uri.startswith(('package:flutter/','package:flutter_test/','package:integration_test/')):
                    raise RuntimeError('Reachable Flutter UI import has no approved standalone shim')
                if uri.startswith('dart:'):continue
                if uri.startswith('package:'):
                    name,relative=uri[len('package:'):].split('/',1)
                    if name not in package_names:raise RuntimeError('Unknown imported package')
                    if name!='tandemlog':continue
                    target=(lib/relative).resolve()
                else:target=(source.parent/uri).resolve()
                if not (target.is_relative_to(lib) or target.is_relative_to(tools)):
                    raise RuntimeError('Project import escaped sealed source/tool roots')
                pending.append(target)
    return sorted(str(p) for p in seen)

def create_owned_source_fork(repo, output):
    original=repo/'.dart_tool/package_config.json';config=json.loads(original.read_text())
    names=[p['name'] for p in config['packages']]
    if len(names)!=len(set(names)) or names.count('tandemlog')!=1:raise RuntimeError('Invalid package inventory')
    roots={}
    package_libraries={}
    for package in config['packages']:
        uri=urllib.parse.urljoin(original.as_uri(),package['rootUri']);parsed=urllib.parse.urlparse(uri)
        if parsed.scheme!='file' or parsed.fragment or parsed.query:raise RuntimeError('Only local sealed package roots allowed')
        roots[package['name']]=pathlib.Path(urllib.parse.unquote(parsed.path)).resolve()
        package_uri=package.get('packageUri','')
        library_uri=urllib.parse.urljoin(roots[package['name']].as_uri()+'/',package_uri)
        library_parsed=urllib.parse.urlparse(library_uri)
        if library_parsed.scheme!='file' or library_parsed.fragment or library_parsed.query:
            raise RuntimeError('Only local package library roots allowed')
        library=pathlib.Path(urllib.parse.unquote(library_parsed.path)).resolve()
        if not library.is_relative_to(roots[package['name']]):
            raise RuntimeError('Package library escaped sealed package root')
        package_libraries[package['name']]=library
    if roots['tandemlog']!=repo.resolve():raise RuntimeError('Repository package config points at a different source tree')
    if package_libraries['tandemlog']!=(repo/'lib').resolve():raise RuntimeError('Repository package library must be the sealed lib directory')
    if any(p.is_symlink() for p in (repo/'lib').rglob('*')):raise RuntimeError('Source symlinks are not allowlisted')
    fork=output/'source';fork.mkdir();shutil.copytree(repo/'lib',fork/'lib')
    for name in ['pubspec.yaml','pubspec.lock']:shutil.copyfile(repo/name,fork/name)
    (fork/'.dart_tool').mkdir();dependency_pins={}
    for package in config['packages']:
        package_root=roots[package['name']]
        if package['name']!='tandemlog' and any(source.is_symlink() for source in package_libraries[package['name']].rglob('*')):raise RuntimeError('Package library symlinks are not allowlisted')
        if package['name']=='tandemlog':
            package['rootUri']=fork.as_uri()+'/'
            package['packageUri']='lib/'
        else:
            package['rootUri']=package_root.as_uri()+'/'
            for source in package_root.rglob('*'):
                if source.is_file() and (source.suffix in ['.dart','.yaml'] or source.name=='pubspec.lock'):
                    dependency_pins[str(source.resolve())]=digest(source)
    owned=fork/'.dart_tool/package_config.json';write_new(owned,config)
    files=[p for p in fork.rglob('*') if p.is_file() and '.dart_tool' not in p.parts]
    seals={str(p.relative_to(fork)):{'originalSHA256':digest(repo/p.relative_to(fork)),'compiledSHA256':digest(p),'change':'none'} for p in files}
    if any(v['originalSHA256']!=v['compiledSHA256'] for v in seals.values()):raise RuntimeError('Unexpected compiled source extraction change')
    fork_pins={str(p.resolve()):digest(p) for p in fork.rglob('*') if p.is_file()}
    return owned,{**dependency_pins,**fork_pins,str(original):digest(original)},seals,names

def fixture_binding(fixtures):
    result={}
    for size,fixture in fixtures.items():
        manifest=fixture['manifest'];receipt=fixture['receipt']
        if json.loads(manifest.read_text())!=receipt:
            raise RuntimeError('Sealed synthetic fixture manifest changed')
        workspace=pathlib.Path(receipt['workspace'])
        expected=receipt['files']
        actual={str(p.relative_to(workspace)) for p in workspace.rglob('*') if p.is_file()}
        if actual!=set(expected) or any(p.is_symlink() for p in workspace.rglob('*')):
            raise RuntimeError('Sealed synthetic fixture inventory changed')
        if any(digest(workspace/n)!=h for n,h in expected.items()):
            raise RuntimeError('Sealed synthetic fixture changed')
        result[size]=digest(manifest)
    return result

def require_binding(original,current):
    if original!=current:raise RuntimeError('Compiled binary or fixture binding changed')

def actual_resource_bounds():
    relative=next(line.split('::',1)[1] for line in pathlib.Path('/proc/self/cgroup').read_text().splitlines() if line.startswith('0::'))
    cgroup=pathlib.Path('/sys/fs/cgroup')/relative.lstrip('/')
    return {name:(cgroup/name).read_text().strip() for name in
            ['memory.max','memory.swap.max','cpu.max','pids.max']}

def require_release_bounds(bounds):
    try:
        quota,period=map(int,bounds['cpu.max'].split())
        valid=(0<int(bounds['memory.max'])<=6*1024**3 and
               bounds['memory.swap.max']=='0' and
               0<int(bounds['pids.max'])<=128 and 0<quota<=2*period)
    except (KeyError,ValueError,TypeError):
        valid=False
    if not valid:raise RuntimeError('Required physical memory/CPU/process bounds are unavailable or exceed release caps')

def noise_snapshot():
    if resource is None:
        return {}
    values={}
    try:
        cpu=list(map(int,pathlib.Path('/proc/stat').read_text().splitlines()[0].split()[1:]))
        values['hostBusyTicks']=sum(cpu[i] for i in [0,1,2,5,6,7]);values['ticksPerSecond']=os.sysconf('SC_CLK_TCK')
        own=resource.getrusage(resource.RUSAGE_SELF);children=resource.getrusage(resource.RUSAGE_CHILDREN)
        values['ownCpuMicroseconds']=int((own.ru_utime+own.ru_stime+children.ru_utime+children.ru_stime)*1_000_000)
    except (OSError,ValueError,IndexError):pass
    try:
        line=next(x for x in pathlib.Path('/proc/pressure/cpu').read_text().splitlines() if x.startswith('some '))
        values['pressure']=int(dict(x.split('=') for x in line.split()[1:])['total'])
        cg=pathlib.Path('/proc/self/cgroup').read_text().strip().split('::',1)[1]
        own=pathlib.Path(cg).name
        siblings={}
        for unit in pathlib.Path('/sys/fs/cgroup/system.slice').glob('*.service'):
            if unit.name==own: continue
            try:
                stats=dict(x.split() for x in (unit/'cpu.stat').read_text().splitlines())
                siblings[unit.name]=int(stats['usage_usec'])
            except (OSError,KeyError,ValueError): pass
        values['siblings']=siblings; values['ownExcluded']=bool(own.endswith('.service'))
    except (OSError,KeyError,ValueError,StopIteration): pass
    return values

def noise_evidence(before, after, seconds):
    pressure=all('pressure' in x for x in [before,after])
    siblings=all(x.get('ownExcluded') for x in [before,after])
    host=all(all(k in x for k in ['hostBusyTicks','ticksPerSecond','ownCpuMicroseconds']) for x in [before,after])
    if siblings:
        other=sum(max(0,v-before.get('siblings',{}).get(k,v)) for k,v in after.get('siblings',{}).items())
        basis='Other sibling systemd services; own service excluded'
    elif host:
        busy=max(0,after['hostBusyTicks']-before['hostBusyTicks'])*1_000_000/before['ticksPerSecond']
        own=max(0,after['ownCpuMicroseconds']-before['ownCpuMicroseconds'])
        other=max(0,int(busy-own));basis='Host non-idle CPU minus measured own process and all waited child CPU'
    else:other=0;basis='Unavailable; retry ineligible'
    return {'kind':'observed-external-cpu-load','sampleWindowCovered':pressure and (siblings or host),
            'windowSeconds':seconds,'cpuSomeStallMicrosecondsDelta':max(0,after.get('pressure',0)-before.get('pressure',0)),
            'otherCpuMicrosecondsDelta':other,'ownWorkExcluded':siblings or host,'basis':basis,
            'qualification':'Aggregate external pressure during entire attempt; suspected timing noise, not proof that every slow sample was affected.'}

def stop_owned_group(child):
    if os.name=='posix':
        try:os.killpg(child.pid,signal.SIGTERM)
        except ProcessLookupError:pass
    elif child.poll() is None:child.terminate()
    try:child.wait(10)
    except subprocess.TimeoutExpired:
        if os.name=='posix':
            try:os.killpg(child.pid,signal.SIGKILL)
            except ProcessLookupError:pass
        else:child.kill()
        child.wait(5)

def _cleanup_need(value, reason):
    if not value:raise RuntimeError(reason)

def group_members(pgid, deadline):
    """Bounded read-only witnesses; no command lines, new signals or reaping."""
    result = {'observedMonotonic': time.monotonic(), 'complete': True, 'members': []}
    try:
        for item in pathlib.Path('/proc').iterdir():
            if not item.name.isdecimal(): continue
            if time.monotonic() >= deadline:
                result['complete'] = False
                break
            try:
                raw = (item/'stat').read_text()
                fields = raw.rsplit(')', 1)[1].split()
                if int(fields[2]) == pgid:
                    result['members'].append({'pid': int(item.name), 'state': fields[0],
                        'ppid': int(fields[1]), 'pgrp': int(fields[2]),
                        'session': int(fields[3]), 'startTicks': fields[19]})
                    if len(result['members']) >= 128:
                        result['complete'] = False
                        break
            except FileNotFoundError:
                continue  # Exited while inspecting; no claim about its former state.
            except (OSError, ValueError, IndexError) as error:
                result['complete'] = False
                result.setdefault('errors', []).append(type(error).__name__)
    except OSError as error:
        result['complete'] = False
        result['error'] = type(error).__name__
    return result


def wait_group_absent(pgid, deadline, evidence):
    """Observe absence, including reaping; never ignore zombies or add a signal.

    At most one second, within the ORIGINAL stage and batch deadline. A live,
    zombie, reused or unobservable group that persists remains a failure.
    """
    until = min(deadline, time.monotonic()+1)
    evidence['waitDeadlineMonotonic'] = until
    first = True
    while True:
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            evidence['absent'] = True
            evidence['finishedMonotonic'] = time.monotonic()
            _cleanup_need(evidence['finishedMonotonic'] <= deadline,
                    'Original stage/batch deadline exceeded during cleanup')
            return
        if first:
            evidence['firstResidual'] = group_members(pgid, min(until, time.monotonic()+.05))
            first = False
        if time.monotonic() >= until:
            evidence['lastResidual'] = group_members(pgid, min(deadline, time.monotonic()+.05))
            evidence['absent'] = False
            evidence['finishedMonotonic'] = time.monotonic()
            raise RuntimeError('Owned process group remains; stop batch before next cell')
        time.sleep(min(.01, max(0, until-time.monotonic())))


def run_child(command, log, env, timeout):
    before=noise_snapshot(); start=time.monotonic(); deadline=start+timeout
    child=None; result=None; primary=None; identity=None
    try:
        with pathlib.Path(log).open('xb') as stream:
            child=subprocess.Popen(command,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
            stat=(pathlib.Path('/proc')/str(child.pid)/'stat').read_text().rsplit(')',1)[1].split()
            identity={'pid':child.pid,'startTicks':stat[19],'pgrp':int(stat[2]),'session':int(stat[3])}
            code=child.wait(timeout=max(.001,deadline-time.monotonic()))
        seconds=time.monotonic()-start
        result={'exitCode':code,'seconds':seconds,'childPID':child.pid,
                'childAbsent':not pathlib.Path('/proc',str(child.pid)).exists(),
                'childGroupAbsent':False,'logSHA256':digest(log),
                'noise':noise_evidence(before,noise_snapshot(),seconds)}
        return result
    except BaseException as error:
        primary=type(error).__name__+': '+str(error)
        raise
    finally:
        evidence={'primaryError':primary,'leaderIdentity':identity,'childGroupAbsent':False}
        cleanup_error=None
        if child is not None:
            try:
                witness=group_members(child.pid,min(deadline,time.monotonic()+.05))
                evidence['beforeCallback']=witness
                # An unreaped live leader reserves its PID/group identity. Once
                # reaped, only observe group absence; do not signal a reused ID.
                if child.poll() is None:
                    current=(pathlib.Path('/proc')/str(child.pid)/'stat').read_text().rsplit(')',1)[1].split()
                    leader={'pid':child.pid,'startTicks':current[19],
                        'pgrp':int(current[2]),'session':int(current[3])}
                    evidence['signalLeaderIdentity']=leader
                    _cleanup_need(identity==leader and leader['pgrp']==leader['session']==child.pid,
                        'Original leader identity changed; refuse group signal')
                    stop_owned_group(child)
                else:
                    evidence['leaderAlreadyReaped']=True
                wait_group_absent(child.pid,deadline,evidence)
                evidence['childGroupAbsent']=True
                if result is not None:result['childGroupAbsent']=True
            except BaseException as error:
                cleanup_error=error;evidence['cleanupError']=type(error).__name__+': '+str(error)
        write_new(str(log)+'.cleanup.json',evidence)
        if cleanup_error is not None and primary is None:raise cleanup_error

def measurements(log):
    rows=[]; complete=False
    for line in pathlib.Path(log).read_text().splitlines():
        try: item=json.loads(line)
        except ValueError: continue
        if not isinstance(item,dict):continue
        if item.get('measurement')=='broad-all-pass':complete=True
        if item.get('measurement')=='broad-action':
            rows.append({'action':item['action'],'index':item['index'],'warmup':item['warmup'],'microseconds':item['microseconds']})
        if item.get('measurement')=='broad-startup' and item.get('index',-1)>=0:
            cold=item['freshProfile'];prefix='startup.cold' if cold else 'startup.warm'
            fields={'total':'totalUs','history':'historyUs','taskAttach':'taskAttachUs'}
            if not cold:fields.update(proof='proofUs',cacheRestore='cacheRestoreUs')
            for suffix,key in fields.items():
                rows.append({'action':prefix+'.'+suffix,'index':item['index'],'warmup':item['warmup'],'microseconds':item[key]})
    return rows,complete

def validate_cost_measurements(log):
    observed=0
    for line in pathlib.Path(log).read_text().splitlines():
        try:item=json.loads(line)
        except ValueError:continue
        if not isinstance(item,dict) or item.get('measurement')!='broad-action':continue
        cost=item.get('costs',{});coverage=cost.get('exclusiveCoverageUs',{})
        if (cost.get('complete') is not True or cost.get('reconciled') is not True
                or not coverage or any(type(v) is not int or v<0 for v in coverage.values())
                or sum(coverage.values())!=item['microseconds']
                or cost.get('totalUs')!=item['microseconds']
                or cost.get('coverageSumUs')!=item['microseconds']):
            raise RuntimeError('Missing, incomplete or unreconciled diagnostic action costs')
        observed+=1
    if not observed:raise RuntimeError('Diagnostic run produced no action cost intervals')
    return observed

def fixture_argument(spec):
    """Closed versioned shapes; old integer CLI values keep their meaning."""
    if type(spec) is int and spec in (60, 1320, 2640):
        return str(spec)
    if (type(spec) is dict and set(spec) == {'baseRecords', 'growthKind'} and
            type(spec['baseRecords']) is int and spec['baseRecords'] == 2640 and
            spec['growthKind'] == 'food'):
        return 'food:2640'
    raise RuntimeError('Unknown versioned synthetic fixture specification')

def scaling_specs(limits):
    extra = limits.get('additionalPairedScaling')
    if type(extra) is not dict or set(extra) != {'food-own-history'}:
        raise RuntimeError('Additive Food-own-history comparison is required')
    specs = {'task-own-history': limits['pairedScaling'], **extra}
    if (specs['task-own-history'].get('growthKind', 'task') != 'task' or
            specs['food-own-history'].get('growthKind') != 'food'):
        raise RuntimeError('Invalid paired growth module')
    used = set()
    for spec in specs.values():
        small, large = spec['smallSize'], spec['largeSize']
        if (small == large or fixture_argument(limits['historySizes'][small]) != '1320' or
                fixture_argument(limits['historySizes'][large]) !=
                ('food:2640' if spec.get('growthKind', 'task') == 'food' else '2640')):
            raise RuntimeError('Paired fixture specification mismatch')
        used.update((small, large))
    if used != set(limits['historySizes']) or used != set(limits['actionsBySize']):
        raise RuntimeError('Unpaired fixture or missing size coverage')
    return specs

def may_rerun_all(decisions, paired, attempt, executions, original, current):
    """Every implicated size, across BOTH pairs, needs independent noise."""
    evaluations = list(decisions.values()) + [decision for _, decision in paired]
    if any(d.status == 'correctness-failed' for d in evaluations):
        return False
    implicated = {size for size, d in decisions.items() if d.status == 'timing-failed'}
    implicated.update(spec['largeSize'] for spec, d in paired if d.status == 'timing-failed')
    failure = Evaluation('timing-failed', ('absolute-or-paired',), {})
    return bool(implicated) and all(
        may_rerun(failure, attempt, executions[size]['noise'], original, current)
        for size in implicated
    )

def main():
    parser=argparse.ArgumentParser()
    for option in ['repo','dart','native-library','sqlite-library','output']:parser.add_argument('--'+option,required=True,type=pathlib.Path)
    parser.add_argument('--expected-limits-sha256',help='Required release workflow binding to committed versioned limits; no alternate limits path is accepted.')
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--measure-only',action='store_true',help='Collect calibration data; never reports release-gate acceptance.')
    mode.add_argument('--hosted-advisory',action='store_true',help='Require full hosted correctness, bindings, coverage and resource caps; timing misses remain advisory, never reference acceptance.')
    parser.add_argument('--reference-request',type=pathlib.Path,help='Exact source-bound controlled-host qualification request; enforcing mode only.')
    parser.add_argument('--diagnose-costs',action='store_true',help='Opt-in API/queue/transaction/provider interval accounting; requires --measure-only and never establishes release performance.')
    args=parser.parse_args()
    if args.diagnose_costs and not args.measure_only:
        parser.error('--diagnose-costs requires --measure-only; instrumented timings cannot satisfy release acceptance')
    if args.reference_request and (args.measure_only or args.hosted_advisory):
        parser.error('--reference-request requires uninstrumented enforcing mode')
    if not sys.platform.startswith('linux'):
        parser.error('The standalone AOT performance runner requires Linux; policy tests are portable.')
    root=args.output.resolve();root.mkdir(mode=0o700,parents=False,exist_ok=False)
    tools=pathlib.Path(__file__).resolve().parent;limits_path=tools/'limits-v1.json';limits=json.loads(limits_path.read_text());limits['sha256']=digest(limits_path)
    if not args.measure_only and (limits.get('releaseReady') is not True or args.expected_limits_sha256!=limits['sha256']):raise SystemExit('Versioned limits are inactive or not workflow-bound; release gate fails closed.')
    comparisons=scaling_specs(limits)
    validate_registered_coverage(json.loads((tools/'coverage-v1.json').read_text()),limits,comparisons)
    pins=source_pins(args.repo.resolve(),tools);packages,compiled_pins,compiled_seals,package_names=create_owned_source_fork(args.repo.resolve(),root)
    imports=validate_project_imports(tools/'benchmark.dart',root/'source',package_names)
    if not args.measure_only and tools!=(args.repo.resolve()/'tool/performance'):raise SystemExit('Release tooling must come from this exact repository checkout')
    sdk=args.dart.resolve().parent.parent
    if not (sdk/'lib/_internal/vm_platform_strong.dill').is_file() or not (sdk/'bin/utils/gen_snapshot').is_file():
        raise RuntimeError('Use the actual reviewed Dart SDK binary, not a Flutter shell wrapper')
    for folder in [sdk/'lib/_internal',sdk/'bin/snapshots']:
        for file in folder.glob('*'):
            if file.is_file() and file.suffix in ['.dill','.snapshot']:compiled_pins[str(file)]=digest(file)
    gen=sdk/'bin/utils/gen_snapshot'
    if gen.is_file():compiled_pins[str(gen)]=digest(gen)
    toolpins={str(p.resolve()):digest(p) for p in [args.dart,packages,args.native_library,args.sqlite_library,limits_path]}
    bounds=actual_resource_bounds()
    if not args.measure_only:require_release_bounds(bounds)
    reference = request_context(args.repo.resolve(),args.reference_request,root,bounds) if args.reference_request else None
    package_contract_sha=package_contract(read_reference_json(args.repo.resolve()/'.dart_tool/package_config.json'))
    if reference is not None:
        check_reference_toolchain({'sourcePins':pins,'toolPins':toolpins,
          'compiledSourceAndDependencyPins':compiled_pins,'packageContractSHA256':package_contract_sha},reference_profile(args.repo.resolve()))
    request_digest = digest(args.reference_request) if args.reference_request else None
    def check_pins():
        if pins!=source_pins(args.repo.resolve(),tools) or any(digest(p)!=h for p,h in {**toolpins,**compiled_pins}.items()):raise RuntimeError('Source/tool/limits pins changed')
        if not args.measure_only and actual_resource_bounds()!=bounds:
            raise RuntimeError('Resource bounds changed')
        if args.reference_request and (digest(args.reference_request)!=request_digest or request_context(args.repo.resolve(),args.reference_request,root,actual_resource_bounds())!=reference):
            raise RuntimeError('Reference request/source/environment changed')
    env=os.environ.copy();env.update(LD_PRELOAD=str(args.sqlite_library.resolve()),TANDEMLOG_TEXT_LIBRARY=str(args.native_library.resolve()),DART_SUPPRESS_ANALYTICS='true',CI='true')
    report={'environment':runtime_environment(),'resourceBounds':bounds,'schemaVersion':1,'scope':'AOT storage/application/readmodel; actual UI gate separate','releaseGateAccepted':False,'correctnessAccepted':False,'timingRole':'hosted-advisory' if args.hosted_advisory else 'measure-only' if args.measure_only else 'enforcing','measureOnly':args.measure_only,'costDiagnosticsEnabled':args.diagnose_costs,'sourcePins':pins,'toolPins':toolpins,'compiledSourceAndDependencyPins':compiled_pins,'compiledFileSeals':compiled_seals,'projectImportClosure':imports,'sourceRewrites':[],'shimAllowlist':[],'attempts':[],'rerunsUsed':0}
    report['startedAtUTC']=utc()
    report['packageContractSHA256']=package_contract_sha
    if reference is not None:report['referenceBinding']=reference
    try:
        binary=root/'benchmark';command=[str(args.dart.resolve()),'compile','exe','--packages='+str(packages),str(tools/'benchmark.dart'),'-o',str(binary)]
        report['compile']=run_child(command,root/'compile.log',env,180);check_pins()
        if report['compile']['exitCode']!=0:raise RuntimeError('AOT compile failed; log retained')
        if not binary.is_file() or binary.is_symlink():
            raise RuntimeError('Compiler did not produce the owned regular binary')
        report['binarySHA256']=digest(binary)
        binary.chmod(0o700)
        report['binaryMode']=oct(binary.stat().st_mode & 0o777)
        if digest(binary)!=report['binarySHA256'] or not os.access(binary,os.X_OK):
            raise RuntimeError('Compiled binary executable permission failed')
        fixtures={}
        sealed_binary=report['binarySHA256']
        for size,spec in limits['historySizes'].items():
            if digest(binary)!=sealed_binary:raise RuntimeError('Compiled binary changed')
            check_pins()
            fixture=root/('fixture-'+size);generated=run_child([str(binary),'generate',str(fixture),str(args.native_library.resolve()),fixture_argument(spec)],root/(size+'-generate.log'),env,180)
            if digest(binary)!=sealed_binary:raise RuntimeError('Compiled binary changed')
            check_pins()
            if generated['exitCode']!=0:raise RuntimeError('Synthetic fixture generation failed')
            manifest=fixture/'fixture.json';receipt=json.loads(manifest.read_text())
            fixtures[size]={'manifest':manifest,'receipt':receipt,'generation':generated}
        report['fixtures']={size:{'manifestSHA256':digest(f['manifest']),'contract':f['receipt'],'generation':f['generation']} for size,f in fixtures.items()}
        def binding():
            check_pins()
            return {'source':hashlib.sha256(json.dumps(pins,sort_keys=True).encode()).hexdigest(),'fixtures':fixture_binding(fixtures),'limits':limits['sha256'],'binary':digest(binary)}
        original=binding();report['pairedScalingAttempts']=[]
        for attempt in range(2):
            decisions={};executions={};summaries={}
            for size,fixture in fixtures.items():
                output=root/(size+'-attempt-'+str(attempt));log=root/(size+'-attempt-'+str(attempt)+'.log')
                require_binding(original,binding())
                execution=run_child([str(binary),'diagnose' if args.diagnose_costs else 'run',str(output),str(args.native_library.resolve()),str(fixture['manifest'])],log,env,600)
                require_binding(original,binding())
                if args.diagnose_costs and execution['exitCode']==0:
                    validate_cost_measurements(log)
                rows,complete=measurements(log);result={'size':size,'correctnessPassed':execution['exitCode']==0 and complete and execution['childAbsent'] and execution['childGroupAbsent'],'limitsSHA256':limits['sha256'],'observations':rows}
                decision=evaluate(result,limits);item={'size':size,'attempt':attempt,'execution':execution,'binding':original,'result':result,'status':decision.status,'failures':decision.failures,'summaries':decision.summaries};report['attempts'].append(item);write_new(root/(size+'-attempt-'+str(attempt)+'-result.json'),item)
                decisions[size]=decision;executions[size]=execution;summaries[size]=decision.summaries
                if decision.status=='correctness-failed':raise RuntimeError('Correctness/coverage failed; retry prohibited')
            paired=[]
            for name,spec in comparisons.items():
                decision=evaluate_scaling(summaries,spec,{size:f['receipt'] for size,f in fixtures.items()})
                paired.append((spec,decision))
                report['pairedScalingAttempts'].append({'attempt':attempt,'comparison':name,'smallSize':spec['smallSize'],'largeSize':spec['largeSize'],'status':decision.status,'failures':decision.failures,'comparisons':decision.summaries})
                if decision.status=='correctness-failed':raise RuntimeError('Paired fixture shape/coverage failed; retry prohibited')
            failures=[failure for d in decisions.values() for failure in d.failures]+[failure for _,d in paired for failure in d.failures]
            if not may_complete_with_advisory_timing([*decisions.values(),*(decision for _,decision in paired)]):
                raise RuntimeError('Correctness/structure cannot be advisory')
            if not failures:break
            if args.measure_only or args.hosted_advisory:
                break
            if may_rerun_all(decisions,paired,attempt,executions,original,binding()):
                report['rerunsUsed']=1;continue
            raise RuntimeError('Absolute or paired timing limit exceeded; no eligible further rerun')
        require_binding(original,binding());report['allPinsMatch']=True;report['measurementCompleted']=True;report['correctnessAccepted']=True;report['timingLimitsPassed']=not failures;report['releaseGateAccepted']=not (args.measure_only or args.hosted_advisory)
        return 0
    except BaseException as error:
        report['error']=str(error);return 1
    finally:
        report['finishedAtUTC']=utc()
        write_new(root/'gate-result.json',report)

if __name__=='__main__':sys.exit(main())
