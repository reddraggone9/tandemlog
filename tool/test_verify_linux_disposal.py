import unittest
from verify_linux_disposal import validate_trace


def event(kind, name, **fields):
    values = {'event': kind, 'object': name, 'thread': 42, **fields}
    return 'TANDEMLOG_LIFECYCLE_PROBE ' + ' '.join(f'{k}={v}' for k, v in values.items())


def complete_trace():
    rows = [event('watch', n) for n in ('window', 'view', 'engine')]
    rows += [event('detach', 'window'), event('destroyed', 'window'),
             event('destroyed', 'view'), event('finalized', 'view'),
             event('finalized', 'window'), event('finalized', 'engine')]
    rows += [event('run-return', n, watched=1, destroyed=int(n != 'engine'), finalized=1)
             for n in ('window', 'view', 'engine')]
    return rows


class LinuxDisposalEvidence(unittest.TestCase):
    def test_complete_same_thread_disposal_precedes_loop_return(self):
        result = validate_trace('\n'.join(complete_trace()), 42)
        self.assertEqual(result['objectsFinalizedBeforeLoopReturn'], ['engine', 'view', 'window'])
        self.assertTrue(result['sameOwningThread'])

    def test_clean_exit_without_real_engine_finalization_is_rejected(self):
        rows = [r for r in complete_trace() if 'event=finalized object=engine' not in r]
        with self.assertRaisesRegex(RuntimeError, 'remains live'):
            validate_trace('\n'.join(rows), 42)
        with self.assertRaises(RuntimeError):
            validate_trace('', 42)

    def test_late_foreign_duplicate_and_false_state_are_rejected(self):
        base = complete_trace()
        late = [r for r in base if 'event=finalized object=engine' not in r]
        late.append(event('finalized', 'engine'))
        variations = [late, base[:-1], [base[0], *base],
                      [r.replace('thread=42', 'thread=43') for r in base],
                      [r.replace('finalized=1', 'finalized=0') for r in base],
                      [r.replace('destroyed=1', 'destroyed=0') for r in base]]
        for rows in variations:
            with self.subTest(rows=rows):
                with self.assertRaises(RuntimeError):
                    validate_trace('\n'.join(rows), 42)


if __name__ == '__main__':
    unittest.main()
