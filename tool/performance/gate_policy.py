"""Deterministic policy for the standalone AOT performance gate.
Timing reruns never waive correctness and never change versioned limits.
"""
from dataclasses import dataclass
import statistics
import math

@dataclass(frozen=True)
class Evaluation:
    status: str
    failures: tuple
    summaries: dict

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
    summaries, failures = {}, []
    for action, samples in groups.items():
        warm = [s for s in samples if s.get("warmup") is True]
        measured = [s for s in samples if s.get("warmup") is False]
        if (len(samples) != limits["warmups"]+limits["samples"] or len(warm) != limits["warmups"] or
                len(measured) != limits["samples"] or
                any(type(s.get("index")) is not int for s in samples) or
                [s.get("index", -1) for s in samples] != list(range(len(samples))) or
                any(s["warmup"] != (s["index"] < limits["warmups"]) for s in samples)):
            return Evaluation("correctness-failed", ("sample-count-or-order",), {})
        values = [s["microseconds"] / 1000 for s in measured]
        summary = {"allSamplesMs": values, "medianMs": statistics.median(values),
                   "maxMs": max(values), "warmupSamplesMs": [s["microseconds"]/1000 for s in warm]}
        summaries[action] = summary
        bound = expected[action]
        if any(type(bound.get(k)) not in (int, float) or not math.isfinite(bound[k]) or bound[k] <= 0
               for k in ("medianMs", "maxMs")):
            return Evaluation("correctness-failed", ("invalid-limit",), {})
        if (summary["medianMs"] > bound["medianMs"] or
                summary["maxMs"] > bound["maxMs"]):
            failures.append(action)
    return Evaluation("timing-failed" if failures else "passed", tuple(failures), summaries)

def external_noise_overlapped(evidence):
    """Both CPU pressure and independent unrelated work are required.
    Own CPU quota throttling, a slow sample, or a caller's assertion is insufficient.
    """
    try:
        duration = evidence["windowSeconds"]
        return (evidence["kind"] == "observed-external-cpu-load" and
                evidence["sampleWindowCovered"] is True and duration > 0 and
                evidence["cpuSomeStallMicrosecondsDelta"] / (duration*1_000_000) >= .25 and
                evidence["otherCpuMicrosecondsDelta"] / (duration*1_000_000) >= .5 and
                evidence["ownWorkExcluded"] is True)
    except (KeyError, TypeError, ZeroDivisionError):
        return False

def may_rerun(evaluation, attempt, noise, original_binding, current_binding):
    return (attempt == 0 and evaluation.status == "timing-failed" and
            original_binding == current_binding and external_noise_overlapped(noise))


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
                   for k in ('maxMedianRatio', 'medianAdditiveMs', 'maxMaximumRatio', 'maximumAdditiveMs')):
                return Evaluation('correctness-failed', ('invalid-scaling-limit',), {})
            median_bound = left['medianMs']*rule['maxMedianRatio']+rule['medianAdditiveMs']
            max_bound = left['maxMs']*rule['maxMaximumRatio']+rule['maximumAdditiveMs']
            result[action] = {'smallMedianMs':left['medianMs'],'largeMedianMs':right['medianMs'],
                              'medianBoundMs':median_bound,'smallMaximumMs':left['maxMs'],
                              'largeMaximumMs':right['maxMs'],'maximumBoundMs':max_bound}
            if right['medianMs'] > median_bound or right['maxMs'] > max_bound:
                failures.append('scaling:'+action)
        return Evaluation('timing-failed' if failures else 'passed',tuple(failures),result)
    except (KeyError,TypeError):
        return Evaluation('correctness-failed',('paired-shape-or-coverage',),{})
