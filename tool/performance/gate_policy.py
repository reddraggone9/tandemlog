"""Deterministic policy for the standalone AOT performance gate.

Lee 2026-10-31: one sample per action per shape, no warmups, judged against the median
limits. First-pass misses rerun once, automatically, in the same invocation; a run fails
only when the same label misses both times. Correctness never reruns and limits never change.
"""
from dataclasses import dataclass
import math

GATE_RULE = 'single-sample-confirm-v1'

@dataclass(frozen=True)
class Evaluation:
    status: str
    failures: tuple
    summaries: dict

def may_complete_with_advisory_timing(evaluations):
    """Timing may be advisory; unknown/structural/correctness states never are."""
    values = list(evaluations)
    return bool(values) and all(value.status in ('passed', 'timing-failed')
                                for value in values)

def validate_registered_coverage(coverage, limits, comparisons):
    """Reject registry/budget drift before compiling or measuring a workload."""
    ids = coverage.get("storageApplicationActionIds")
    if (not isinstance(ids, list) or not ids or
            any(not isinstance(action, str) or not action.strip() or
                action != action.strip() for action in ids) or
            len(ids) != len(set(ids))):
        raise ValueError("Registered performance coverage IDs must be unique nonempty strings")
    registered = set(ids)
    sizes = limits.get("actionsBySize")
    if not isinstance(sizes, dict) or not sizes:
        raise ValueError("Registered performance coverage requires per-size budgets")
    for size, actions in sizes.items():
        if not isinstance(actions, dict) or set(actions) != registered:
            raise ValueError("Registered performance coverage/budget IDs differ: " + str(size))
        for action, budget in actions.items():
            if not isinstance(budget, dict) or any(
                    type(budget.get(key)) not in (int, float) or
                    not math.isfinite(budget[key]) or budget[key] <= 0
                    for key in ("medianMs", "maxMs")):
                raise ValueError("Registered performance coverage has invalid budget: " + action)
    if not isinstance(comparisons, dict) or not comparisons:
        raise ValueError("Registered performance coverage requires growth comparisons")
    for name, spec in comparisons.items():
        actions = spec.get("rules") if isinstance(spec, dict) else None
        if not isinstance(actions, dict) or set(actions) != registered:
            raise ValueError("Registered performance coverage/growth IDs differ: " + str(name))
    return tuple(ids)

def evaluate(result, limits):
    if result.get("correctnessPassed") is not True:
        return Evaluation("correctness-failed", ("correctness",), {})
    if result.get("limitsSHA256") != limits["sha256"]:
        return Evaluation("correctness-failed", ("limits-binding",), {})
    size = result.get("size")
    expected = limits["actionsBySize"].get(size)
    if not expected:
        return Evaluation("correctness-failed", ("unknown-size",), {})
    groups = {}
    for sample in result.get("observations", []):
        action, value = sample.get("action"), sample.get("microseconds")
        if action not in expected or type(value) is not int or value < 0 or type(sample.get("warmup")) is not bool:
            return Evaluation("correctness-failed", ("invalid-observation",), {})
        groups.setdefault(action, []).append(sample)
    if set(groups) != set(expected):
        return Evaluation("correctness-failed", ("coverage",), {})
    if limits.get("gateRule") != GATE_RULE or limits.get("warmups") != 0 or limits.get("samples") != 1:
        return Evaluation("correctness-failed", ("sample-policy",), {})
    summaries, failures = {}, []
    for action, samples in groups.items():
        if len(samples) != 1 or type(samples[0].get("index")) is not int or samples[0]["index"] != 0 or samples[0]["warmup"]:
            return Evaluation("correctness-failed", ("sample-count-or-order",), {})
        bound = expected[action].get("medianMs")
        if type(bound) not in (int, float) or not math.isfinite(bound) or bound <= 0:
            return Evaluation("correctness-failed", ("invalid-limit",), {})
        summaries[action] = {"sampleMs": samples[0]["microseconds"] / 1000}
        if summaries[action]["sampleMs"] > bound:
            failures.append(action)
    return Evaluation("timing-failed" if failures else "passed", tuple(failures), summaries)

def growth_bound(small_ms, rule):
    return small_ms*rule['maxMedianRatio']+rule['medianAdditiveMs']


def evaluate_scaling(summaries_by_size, scaling, contracts):
    """Check paired history growth after proving the live state is identical."""
    try:
        small, large = scaling['smallSize'], scaling['largeSize']
        a, b = contracts[small], contracts[large]
        kind = scaling.get('growthKind', 'task')
        count_fields = ('initialHistoricalRecords', 'baseHistoricalRecords',
                        'growthHistoricalRecords', 'actualPhysicalRecords',
                        'initialTaskEffects', 'initialFoodEffects', 'growthTaskEffects',
                        'growthFoodEffects', 'taskEffects', 'foodEffects', 'taskRows', 'foodContainers')
        if (kind not in ('task', 'food') or
                any(type(c.get(k)) is not int or c[k] < 0 for c in (a, b) for k in count_fields)):
            return Evaluation('correctness-failed', ('paired-growth-contract',), {})
        growth = b['growthHistoricalRecords']
        module_growth = (
            a['growthKind'] == 'none' and b['growthKind'] == kind and
            a['initialTaskEffects'] == b['initialTaskEffects'] and
            a['initialFoodEffects'] == b['initialFoodEffects'] and
            a['initialTaskEffects'] + a['initialFoodEffects'] == a['initialHistoricalRecords'] and
            a['baseHistoricalRecords'] == a['initialHistoricalRecords'] and
            b['baseHistoricalRecords'] - b['initialHistoricalRecords'] == growth and
            a['growthTaskEffects'] == 0 and a['growthFoodEffects'] == 0 and
            b['growthTaskEffects'] == (growth if kind == 'task' else 0) and
            b['growthFoodEffects'] == (growth if kind == 'food' else 0) and
            b['taskEffects'] - a['taskEffects'] == b['growthTaskEffects'] and
            b['foodEffects'] - a['foodEffects'] == b['growthFoodEffects'])
        same = (a['syntheticOnly'] is True and b['syntheticOnly'] is True and
                a['currentStateSHA256'] == b['currentStateSHA256'] and
                a['taskRows'] == b['taskRows'] and a['foodContainers'] == b['foodContainers'] and
                len(a['initialPrefixSHA256']) == 3 and a['initialPrefixSHA256'] == b['initialPrefixSHA256'] and
                a['initialHistoricalRecords'] == b['initialHistoricalRecords'] and
                a['growthHistoricalRecords'] == 0 and b['growthHistoricalRecords'] > 0 and
                b['actualPhysicalRecords']-a['actualPhysicalRecords'] == b['growthHistoricalRecords'])
        rules = scaling['rules']
        if not same or not module_growth or set(summaries_by_size[small]) != set(rules) or set(summaries_by_size[large]) != set(rules):
            return Evaluation('correctness-failed', ('paired-shape-or-coverage',), {})
        failures, result = [], {}
        for action, rule in rules.items():
            left, right = summaries_by_size[small][action], summaries_by_size[large][action]
            if any(type(rule.get(k)) not in (int, float) or not math.isfinite(rule[k]) or rule[k] < 0
                   for k in ('maxMedianRatio', 'medianAdditiveMs')):
                return Evaluation('correctness-failed', ('invalid-scaling-limit',), {})
            bound = growth_bound(left['sampleMs'], rule)
            result[action] = {'smallSampleMs': left['sampleMs'], 'largeSampleMs': right['sampleMs'], 'boundMs': bound}
            if right['sampleMs'] > bound:
                failures.append('scaling:'+action)
        return Evaluation('timing-failed' if failures else 'passed',tuple(failures),result)
    except (KeyError,TypeError):
        return Evaluation('correctness-failed',('paired-shape-or-coverage',),{})


def first_pass_failures(absolute, paired):
    """Every first-pass miss as a label: SIZE:ACTION or COMPARISON:scaling:ACTION."""
    return sorted({size+':'+f for size, d in absolute.items() for f in d.failures} |
                  {name+':'+f for name, d in paired.items() for f in d.failures})


def observation_families(results):
    """{size: {action: family}} from first-pass rows; each family must be a plain name."""
    found = {}
    for size, result in results.items():
        for row in result['observations']:
            family = row.get('family')
            if not isinstance(family, str) or not family.replace('-', '').isalnum():
                raise ValueError('Observation has no valid family: '+size+':'+str(row.get('action')))
            found.setdefault(size, {})[row['action']] = family
    return found


def rerun_plan(absolute, paired, specs, families):
    """Sorted (size, family) units. Actions chain within a family, so a whole family reruns.

    A growth miss reruns both sides of its pair; one process serves every label it covers.
    """
    units = {(size, families[size][action]) for size, d in absolute.items() for action in d.failures}
    for name, decision in paired.items():
        for failure in decision.failures:
            action = failure.removeprefix('scaling:')
            units.update((size, families[size][action]) for size in (specs[name]['smallSize'], specs[name]['largeSize']))
    return sorted(units)


def valid_rerun_rows(rows, family, actions):
    """One unwarmed sample for exactly the family's first-pass actions; nothing else counts."""
    return (isinstance(rows, list) and sorted(r.get('action', '') for r in rows) == sorted(actions) and
            all(r.get('family') == family and type(r.get('index')) is int and r['index'] == 0 and
                r.get('warmup') is False and type(r.get('microseconds')) is int and r['microseconds'] >= 0
                for r in rows))


def judge_reruns(absolute, paired, reruns, limits, specs):
    """Judge first-pass misses from rerun values only. reruns: {size: {action: ms}}.

    A growth pair is judged from the rerun values of BOTH sides. Other labels over their bound
    in a rerun are recorded for a person but not judged.
    """
    judgments, other = [], []
    judged = set()
    for size, decision in absolute.items():
        for action in decision.failures:
            bound = limits['actionsBySize'][size][action]['medianMs']
            value = reruns[size][action]
            judged.add(size+':'+action)
            judgments.append({'label': size+':'+action, 'kind': 'absolute', 'firstPassMs': decision.summaries[action]['sampleMs'],
                              'rerunMs': value, 'boundMs': bound, 'failedAgain': value > bound})
    for name, decision in paired.items():
        spec = specs[name]
        for failure in decision.failures:
            action = failure.removeprefix('scaling:')
            small, large = reruns[spec['smallSize']][action], reruns[spec['largeSize']][action]
            bound = growth_bound(small, spec['rules'][action])
            judged.add(name+':'+failure)
            judgments.append({'label': name+':'+failure, 'kind': 'growth', 'firstPass': decision.summaries[action],
                              'rerun': {'smallSampleMs': small, 'largeSampleMs': large, 'boundMs': bound},
                              'failedAgain': large > bound})
    for size, values in reruns.items():
        for action, value in values.items():
            if size+':'+action not in judged and value > limits['actionsBySize'][size][action]['medianMs']:
                other.append({'label': size+':'+action, 'rerunMs': value, 'boundMs': limits['actionsBySize'][size][action]['medianMs']})
    for name, spec in specs.items():
        for action in set(reruns.get(spec['smallSize'], {})) & set(reruns.get(spec['largeSize'], {})):
            label = name+':scaling:'+action
            small, large = reruns[spec['smallSize']][action], reruns[spec['largeSize']][action]
            bound = growth_bound(small, spec['rules'][action])
            if label not in judged and large > bound:
                other.append({'label': label, 'rerun': {'smallSampleMs': small, 'largeSampleMs': large, 'boundMs': bound}})
    judgments.sort(key=lambda item: item['label'])
    other.sort(key=lambda item: item['label'])
    return {'judgments': judgments, 'notJudgedOverBound': other,
            'confirmedFailures': [item['label'] for item in judgments if item['failedAgain']]}
