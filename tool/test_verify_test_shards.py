import json
import unittest
from pathlib import Path

from verify_test_shards import dart_round, registration_lines, verify

ROOT = Path(__file__).resolve().parent.parent

SUITE = '''import 'x.dart';

void main() {
  binding();
  registerAlphaTests();
  registerBetaTests();
  testWidgets('direct', (tester) async {
    nested();
  });
}
'''


def report(tests, success=True, failed=None):
    """Build a package:test JSON report for (name, root_line) tests."""
    events = [{'type': 'start'},
              {'type': 'testStart', 'test': {'id': 0, 'name': 'loading suite'}},
              {'type': 'testDone', 'testID': 0, 'result': 'success', 'hidden': True}]
    for number, (name, root) in enumerate(tests, 1):
        events.append({'type': 'testStart', 'test': {
            'id': number, 'name': name, 'url': 'package:flutter_test/x.dart',
            'line': 174, 'root_line': root}})
        events.append({'type': 'testDone', 'testID': number, 'hidden': False,
                       'result': 'failure' if name == failed else 'success'})
    events.append({'type': 'done', 'success': success})
    return '\n'.join(json.dumps(event) for event in events)


# Declaration order: alpha (line 5), beta (line 6), then the direct test (line 7).
FULL = [('a1', 5), ('a2', 5), ('a3', 5), ('a4', 5), ('b1', 6), ('b2', 6), ('direct', 7)]


def shards(tests, total):
    """Slice exactly as package:test does."""
    size = len(tests) / total
    return [tests[dart_round(size * i):dart_round(size * (i + 1))] for i in range(total)]


class ShardPartitionGate(unittest.TestCase):
    def test_dart_rounding_matches_package_test(self):
        self.assertEqual([dart_round(v) for v in (0.5, 1.5, 2.5, 3.49)], [1, 2, 3, 3])

    def test_registration_sites_are_main_level_calls(self):
        self.assertEqual(registration_lines(SUITE), {5, 6, 7})

    def test_package_test_partition_is_accepted(self):
        for total in (2, 3, 4, 7):
            summary = verify([report(s) for s in shards(FULL, total)], SUITE)
            self.assertEqual(summary['tests'], len(FULL))
            self.assertEqual(sum(summary['perShard']), len(FULL))

    def test_duplicate_reordered_or_missing_coverage_is_rejected(self):
        first, second = shards(FULL, 2)
        with self.assertRaisesRegex(ValueError, 'ran in shards'):
            verify([report(first), report(first)], SUITE)
        with self.assertRaisesRegex(ValueError, 'contiguous'):
            verify([report(first[:3] + [('b1', 6)]), report([('a4', 5)] + second[1:])], SUITE)
        with self.assertRaisesRegex(ValueError, 'no shard'):
            verify([report(first), report([('a5', 5), ('a6', 5), ('b3', 6)])], SUITE)

    def test_failed_unfinished_or_empty_shards_are_rejected(self):
        first, second = shards(FULL, 2)
        with self.assertRaisesRegex(ValueError, 'did not pass'):
            verify([report(first, failed='a1'), report(second)], SUITE)
        with self.assertRaisesRegex(ValueError, 'finish successfully'):
            verify([report(first), report(second, success=False)], SUITE)
        unfinished = report(second).splitlines()
        unfinished = '\n'.join(line for line in unfinished if '"testID": 1,' not in line)
        with self.assertRaisesRegex(ValueError, 'never completed'):
            verify([report(first), unfinished], SUITE)
        with self.assertRaisesRegex(ValueError, r'ran \d+ tests'):
            verify([report(FULL), report([])], SUITE)
        with self.assertRaisesRegex(ValueError, 'at least two'):
            verify([report(FULL)], SUITE)

    def test_native_suite_has_parseable_registration_sites(self):
        source = (ROOT / 'integration_test/task_flow_test.dart').read_text(encoding='utf-8')
        self.assertGreater(len(registration_lines(source)), 40)

    def test_workflow_runs_every_shard_and_gates_their_union(self):
        workflow = (ROOT / '.github/workflows/validate.yml').read_text(encoding='utf-8')
        job = workflow.split('\n  linux-workflows:', 1)[1].split('\n  windows:', 1)[0]
        shards = job.split('shard: [', 1)[1].split(']', 1)[0].split(',')
        total = len(shards)
        self.assertEqual([int(s) for s in shards], list(range(total)))
        self.assertIn(f'--total-shards {total}', job)
        self.assertIn('--shard-index "$SHARD"', job)
        self.assertIn('integration_test/task_flow_test.dart -d linux', job)
        self.assertIn('--timeout 120s', job)
        gate = workflow.split('\n  linux-workflows-union:', 1)[1].split('\n  windows:', 1)[0]
        self.assertIn('needs: linux-workflows', gate)
        self.assertIn('tool/verify_test_shards.py', gate)
        self.assertIn('native-workflows-{' + ','.join(map(str, range(total))) + '}.json', gate)
        self.assertNotIn('task_flow_test.dart -d linux',
                         workflow.split('\n  linux:', 1)[1].split('\n  linux-workflows:', 1)[0])


if __name__ == '__main__':
    unittest.main()
