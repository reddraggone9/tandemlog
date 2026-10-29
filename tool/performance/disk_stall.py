"""Disk-stall resample rule for reference qualifications (Lee 2026-10-28; standing).

A timing miss gets ONE resample of its label when every measured sample over the
missed bound is accounted for by its durable append (write+fsync): the sample minus
its append time is within the bound, and its CPU time is within the bound. Budgets
are never consulted for change here. The resample re-measures the whole label (its
family's warmups and samples in a fresh process); its samples replace the label's
samples, and every absolute and growth limit is evaluated again. A resampled label
that misses again is an ordinary failure. Original samples stay in the receipt.
"""
import copy
import json
import pathlib

from gate_policy import evaluate, evaluate_scaling

POLICY = 'disk-stall-label-resample-v1'
CPU_COUNTER = 'cgroup.usage_usec'
THROTTLED_COUNTER = 'cgroup.throttled_usec'


def action_diagnostics(log):
    """(action, index) -> family and durable-append/CPU numbers of a benchmark log."""
    found = {}
    for line in pathlib.Path(log).read_text().splitlines():
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if not isinstance(item, dict) or item.get('measurement') != 'broad-action':
            continue
        d = item.get('diagnostics') if isinstance(item.get('diagnostics'), dict) else {}
        deltas = d.get('resourceDeltas') if isinstance(d.get('resourceDeltas'), dict) else {}
        found[item['action'], item['index']] = {
            'family': item.get('family'),
            'resourcesAvailable': d.get('resourcesAvailable'),
            'appendCalls': d.get('appendCalls'),
            'appendMicroseconds': d.get('appendMicroseconds'),
            'cpuMicroseconds': deltas.get(CPU_COUNTER),
            'throttledMicroseconds': deltas.get(THROTTLED_COUNTER),
        }
    return found


def missed_statistics(absolute, paired, specs, limits):
    """(size, action) -> every missed statistic with its bound, absolute and growth."""
    missed = {}
    for size, decision in absolute.items():
        for action in decision.failures:
            summary, budget = decision.summaries[action], limits['actionsBySize'][size][action]
            for statistic, value, bound in (('median', summary['medianMs'], budget['medianMs']),
                                            ('maximum', summary['maxMs'], budget['maxMs'])):
                if value > bound:
                    missed.setdefault((size, action), []).append(
                        {'label': size + ':' + action, 'statistic': statistic, 'measuredMs': value, 'boundMs': bound})
    for name, decision in paired.items():
        for failure in decision.failures:
            action, summary = failure.removeprefix('scaling:'), decision.summaries[failure.removeprefix('scaling:')]
            for statistic, value, bound in (('median', summary['largeMedianMs'], summary['medianBoundMs']),
                                            ('maximum', summary['largeMaximumMs'], summary['maximumBoundMs'])):
                if value > bound:
                    missed.setdefault((specs[name]['largeSize'], action), []).append(
                        {'label': name + ':' + failure, 'statistic': statistic, 'measuredMs': value, 'boundMs': bound})
    return missed


def evaluate_all(results, limits, specs, contracts):
    absolute = {size: evaluate(result, limits) for size, result in results.items()}
    summaries = {size: value.summaries for size, value in absolute.items()}
    paired = {name: evaluate_scaling(summaries, spec, contracts) for name, spec in specs.items()}
    return absolute, paired


def _attributed(sample, info, bound_us):
    wall = sample['microseconds']
    append, cpu, calls = info.get('appendMicroseconds'), info.get('cpuMicroseconds'), info.get('appendCalls')
    return (info.get('resourcesAvailable') is True and type(calls) is int and calls > 0 and
            type(append) is int and 0 < append <= wall and type(cpu) is int and 0 <= cpu <= bound_us and
            wall - append <= bound_us)


def plan(results, diagnostics, limits, specs, contracts, already=()):
    """Return (resamples, unattributed labels) for one attempt's original results.

    Resamples are planned only when they can decide the attempt: every missed label
    must be attributed and none may already have used its one resample.
    """
    absolute, paired = evaluate_all(results, limits, specs, contracts)
    if any(d.status == 'correctness-failed' for d in [*absolute.values(), *paired.values()]):
        return [], ['correctness']
    used = {tuple(item) for item in already}
    planned, unattributed = [], []
    for (size, action), statistics in sorted(missed_statistics(absolute, paired, specs, limits).items()):
        measured = [s for s in results[size]['observations'] if s['action'] == action and s['warmup'] is False]
        info = diagnostics.get(size, {})
        ok, evidence = (size, action) not in used, {}
        for item in statistics:
            bound_us = item['boundMs'] * 1000
            for sample in measured:
                if sample['microseconds'] <= bound_us:
                    continue
                numbers = info.get((action, sample['index']), {})
                ok = ok and _attributed(sample, numbers, bound_us)
                append = numbers.get('appendMicroseconds')
                evidence[sample['index']] = {
                    'index': sample['index'], 'family': numbers.get('family'),
                    'wallMicroseconds': sample['microseconds'],
                    'resourcesAvailable': numbers.get('resourcesAvailable'),
                    'appendCalls': numbers.get('appendCalls'), 'appendMicroseconds': append,
                    'cpuMicroseconds': numbers.get('cpuMicroseconds'),
                    'throttledMicroseconds': numbers.get('throttledMicroseconds'),
                    'withoutAppendMicroseconds': sample['microseconds'] - append if type(append) is int else None}
        families = {value['family'] for value in evidence.values()}
        family = next(iter(families)) if len(families) == 1 else None
        if not ok or not evidence or not isinstance(family, str) or not family:
            unattributed.extend(item['label'] for item in statistics)
            continue
        planned.append({'policy': POLICY, 'size': size, 'action': action, 'family': family,
                        'missed': statistics, 'samples': [evidence[i] for i in sorted(evidence)]})
    if unattributed:
        return [], sorted(unattributed)
    return planned, []


def recorded_diagnostics(resamples):
    """Rebuild the attribution input from a receipt so the verifier can recompute the plan."""
    found = {}
    for item in resamples:
        for sample in item['samples']:
            found.setdefault(item['size'], {})[item['action'], sample['index']] = {
                key: sample.get(key) for key in ('family', 'resourcesAvailable', 'appendCalls',
                                                 'appendMicroseconds', 'cpuMicroseconds', 'throttledMicroseconds')}
    return found


def apply(results, resamples, replacements, limits):
    """Replace each resampled label's full sample set; everything else stays original."""
    if len(resamples) != len(replacements):
        raise ValueError('Missing/extra disk-stall resample')
    effective = copy.deepcopy(results)
    for item, rows in zip(resamples, replacements):
        expected = list(range(limits['warmups'] + limits['samples']))
        if (not isinstance(rows, list) or [r.get('index') for r in rows] != expected or
                any(r.get('action') != item['action'] for r in rows)):
            raise ValueError('Invalid disk-stall resample: ' + item['size'] + ':' + item['action'])
        result = effective[item['size']]
        result['observations'] = [s for s in result['observations'] if s['action'] != item['action']] + copy.deepcopy(rows)
    return effective
