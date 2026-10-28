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


OFFICIAL_RERUN_LIMIT = 1

def diagnostic_did_not_reproduce(diagnostic, prior_request_id, source_sha256, prior_failures):
    """A recorded, non-qualifying diagnostic must cover every prior failure and reproduce none.

    This is the only basis for the single official rerun of an unchanged source identity
    after an enforcing timing-only qualification failure. Budgets are never consulted or
    changed here; a run that skipped a failing label or reproduced one is not eligible.
    """
    try:
        runs = diagnostic["runs"]
        failures = set(prior_failures)
        return (diagnostic["schemaVersion"] == 1 and
                diagnostic["kind"] == "reference-failure-diagnostic-v1" and
                diagnostic["priorRequestId"] == prior_request_id and
                diagnostic["relevantSourceSHA256"] == source_sha256 and
                diagnostic["reproduced"] is False and
                bool(failures) and isinstance(runs, list) and bool(runs) and
                all(run["role"] == "diagnostic" and run["qualifying"] is False and
                    isinstance(run["resultSHA256"], str) and len(run["resultSHA256"]) == 64 and
                    set(run["resultSHA256"]) <= set("0123456789abcdef") and
                    failures <= set(run["checkedFailures"]) and run["reproducedFailures"] == []
                    for run in runs))
    except (KeyError, TypeError):
        return False


# Lee 2026-10-27: on identical relevant source that already passed, a timing miss within normal
# run-to-run variation is a borderline limit, not a regression. The band is a fraction of the
# exceeded bound: q9/q10/q11 measured the same storageAdmission growth at 99.8%/96.3%/101.6%
# of its bound on identical product code, a 5.3-point spread; 5% covers that and nothing like
# q10's 145.5% explicitTask.title.undo maximum. Budgets themselves are never changed here.
BORDERLINE_VARIATION_BAND = 0.05
BORDERLINE_ACCEPTED = 'borderline-accepted'

def classify_borderline(prior_passed_identity, identity, absolute, paired, band=BORDERLINE_VARIATION_BAND, *, limits=None):
    """Verdict for a recomputed enforcing result: passed, borderline-accepted or failed.

    prior_passed_identity is the relevant-source SHA-256 of an already verified passing
    qualification (None when there is none). Absolute and history-growth misses can be
    borderline; correctness/coverage failures or any miss beyond the band fail. Absolute
    misses require the same verified limits used to recompute their evaluations; keep the
    retained summary schema unchanged so earlier qualification receipts still recompute.
    """
    def failed(reason):
        return {'verdict': 'failed', 'reason': reason, 'borderlineMetrics': []}
    if not prior_passed_identity:
        return failed('no prior passing qualification of this relevant source')
    if prior_passed_identity != identity:
        return failed('prior pass is for a different relevant-source identity')
    if not absolute or not paired:
        return failed('incomplete absolute or growth evaluation')
    for name, decision in [*absolute.items(), *paired.items()]:
        if decision.status not in ('passed', 'timing-failed') or \
                (decision.status == 'timing-failed') != bool(decision.failures):
            return failed('correctness/coverage failure: ' + name + ' ' + ','.join(decision.failures))
    metrics = []
    for decisions, is_growth in ((absolute, False), (paired, True)):
        for name, decision in sorted(decisions.items()):
            for failure in decision.failures:
                action = failure.removeprefix('scaling:') if is_growth else failure
                summary = decision.summaries.get(action)
                label = name + ':' + failure
                if not isinstance(summary, dict) or (is_growth and not failure.startswith('scaling:')):
                    return failed('correctness/coverage failure: ' + label)
                if is_growth:
                    metric_keys = (('median', 'largeMedianMs', 'medianBoundMs'),
                                  ('maximum', 'largeMaximumMs', 'maximumBoundMs'))
                    bounds = summary
                else:
                    metric_keys = (('median', 'medianMs', 'medianMs'), ('maximum', 'maxMs', 'maxMs'))
                    bounds = (limits or {}).get('actionsBySize', {}).get(name, {}).get(action, {})
                exceeded = False
                for statistic, measured_key, bound_key in metric_keys:
                    measured, bound = summary.get(measured_key), bounds.get(bound_key)
                    if (type(measured) not in (int, float) or not math.isfinite(measured) or measured < 0 or
                            type(bound) not in (int, float) or not math.isfinite(bound) or bound <= 0):
                        return failed('invalid timing summary or bound: ' + label)
                    if measured <= bound:
                        continue
                    exceeded = True
                    if measured > bound * (1 + band):
                        return failed('%s %s %.4gms is outside the %g%% variation band of its %.4gms bound'
                                      % (label, statistic, measured, band * 100, bound))
                    metrics.append({'label': label, 'statistic': statistic, 'measuredMs': measured,
                                    'boundMs': bound, 'ratioOfBound': round(measured / bound, 6)})
                if not exceeded:
                    return failed('correctness/coverage failure: ' + label + ' reported without a miss')
    if not metrics:
        return {'verdict': 'passed', 'reason': 'all limits passed', 'borderlineMetrics': []}
    return {'verdict': BORDERLINE_ACCEPTED, 'borderlineMetrics': metrics,
            'reason': 'timing misses within the %g%% variation band on identical, already passed source'
                      % (band * 100)}


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
