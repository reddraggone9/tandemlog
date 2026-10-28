#!/usr/bin/env python3
"""Require sharded native workflow reports to partition the one native suite.

package:test assigns shard i the contiguous declaration range
[round(i*n/N), round((i+1)*n/N)) of the same deterministic test list, so the
shards are disjoint and complete by construction. This gate checks the actual
JSON reports instead of trusting that: every shard ran and passed, sizes match
that formula, no test ran in two shards, the shards are ordered slices of one
declaration order, and every registration site in the suite's main() ran.
"""
import argparse
import json
import math
from pathlib import Path
import re
import sys

# Registration sites are direct calls in the suite's main(): shared
# register...Tests() helpers and the suite's own testWidgets declarations.
SITE = re.compile(r'^  (?:register\w+\(\);|testWidgets\()')


def dart_round(value):
    """Dart's num.round(): halves round away from zero (Python rounds to even)."""
    return math.floor(value + 0.5)


def registration_lines(suite_source):
    """Return 1-based lines of top-level registration calls inside main()."""
    lines = suite_source.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith('void main(')), None)
    if start is None:
        raise ValueError('Suite has no top-level main()')
    sites = set()
    for index in range(start + 1, len(lines)):
        if lines[index] == '}':
            break
        if SITE.match(lines[index]):
            sites.add(index + 1)
    else:
        raise ValueError('Suite main() is not closed at column zero')
    if not sites:
        raise ValueError('Suite main() registers no tests')
    return sites


def read_report(text):
    """Return ordered (key, root_line) for passed tests, else raise."""
    starts, done, finished = {}, [], None
    for raw in text.splitlines():
        if not raw.strip():
            continue
        event = json.loads(raw)
        kind = event.get('type')
        if kind == 'testStart':
            starts[event['test']['id']] = event['test']
        elif kind == 'testDone':
            done.append(event)
        elif kind == 'done':
            finished = event
    if finished is None or finished.get('success') is not True:
        raise ValueError('Shard report did not finish successfully')
    tests, completed = [], set()
    for event in done:
        test = starts.get(event['testID'])
        if test is None:
            raise ValueError('Shard report completed an unstarted test')
        completed.add(event['testID'])
        if event.get('hidden'):
            continue
        if event.get('result') != 'success':
            raise ValueError(f'Shard test did not pass: {test["name"]}')
        root = test.get('root_line') or test.get('line')
        if root is None:
            raise ValueError(f'Shard test has no declaration site: {test["name"]}')
        key = (test['name'], test.get('url'), test.get('line'), root)
        tests.append((key, root))
    if set(starts) - completed:
        raise ValueError('Shard report started tests that never completed')
    return tests


def verify(reports, suite_source):
    """Validate reports in shard-index order; return a summary."""
    total_shards = len(reports)
    if total_shards < 2:
        raise ValueError('Sharding requires at least two shard reports')
    shards = [read_report(text) for text in reports]
    total = sum(len(tests) for tests in shards)
    size = total / total_shards
    for index, tests in enumerate(shards):
        expected = dart_round(size * (index + 1)) - dart_round(size * index)
        if not tests or len(tests) != expected:
            raise ValueError(
                f'Shard {index} ran {len(tests)} tests; package:test assigns {expected} of {total}')
    owner = {}
    for index, tests in enumerate(shards):
        for key, _ in tests:
            if owner.setdefault(key, index) != index:
                raise ValueError(f'Test ran in shards {owner[key]} and {index}: {key[0]}')
    order = [root for tests in shards for _, root in tests]
    if order != sorted(order):
        raise ValueError('Shards are not contiguous slices of one declaration order')
    missing = registration_lines(suite_source) - set(order)
    if missing:
        raise ValueError(f'Registration sites ran in no shard: lines {sorted(missing)}')
    return {'shards': total_shards, 'tests': total,
            'perShard': [len(tests) for tests in shards]}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--suite', required=True, type=Path)
    parser.add_argument('reports', nargs='+', type=Path,
                        help='package:test JSON reports in shard-index order')
    args = parser.parse_args()
    try:
        summary = verify([path.read_text() for path in args.reports], args.suite.read_text())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f'Shard verification failed: {error}', file=sys.stderr)
        return 1
    print(json.dumps(summary))
    return 0


if __name__ == '__main__':
    sys.exit(main())
