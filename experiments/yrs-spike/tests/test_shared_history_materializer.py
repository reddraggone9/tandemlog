"""Frozen first: disposable incremental history, separate from editor ownership.

Only synthetic journals/documents are used. Existing 98 cases remain unchanged.
Materializer rejection invalidates its private handle; callers replay originals.
It never provides Save/Undo or mutates any session owner.
"""
import base64
import unittest

from test_contract import Bridge


class SharedHistoryMaterializer(unittest.TestCase):
    def setUp(self):
        self.b = Bridge()
        self.b.ok('reset')

    def materializer(self, name='history', **limits):
        seed = self.b.ok('seed', text='AB')['update']
        return self.b.ok('materializer_new', name=name, seed=seed,
                         limits={'visibleUtf16': 500, **limits})

    def test_H01_original_packets_duplicates_and_concurrent_delivery_match_owned_state(self):
        seed = self.b.ok('seed', text='AB')['update']
        for name, actor in [('a', 10), ('b', 20)]:
            self.b.ok('new', name=name, client=actor, seed=seed)
        ax = self.b.ok('edit', name='a', index=1, insert='X')['update']
        by = self.b.ok('edit', name='b', index=2, insert='Y')['update']
        self.b.ok('apply', name='a', update=by)
        expected = self.b.ok('state', name='a')['update']
        self.materializer()
        for packet in [by, ax, by, ax]:
            self.b.ok('materializer_apply', name='history', update=packet)
        self.assertEqual(self.b.ok('materializer_read', name='history')['text'], 'AXBY')
        self.assertEqual(self.b.ok('materializer_state', name='history')['update'], expected)

    def test_H02_missing_causal_dependency_survives_checkpoint_and_later_arrival(self):
        seed = self.b.ok('seed', text='AB')['update']
        self.b.ok('new', name='a', client=10, seed=seed)
        first = self.b.ok('edit', name='a', index=1, insert='X')['update']
        second = self.b.ok('edit', name='a', index=2, insert='Z')['update']
        self.materializer()
        pending = self.b.ok('materializer_apply', name='history', update=second)
        self.assertTrue(pending['pending'])
        state = self.b.ok('materializer_state', name='history')['update']
        self.b.ok('materializer_cancel', name='history')
        self.b.ok('materializer_new', name='history', seed=state,
                  limits={'visibleUtf16': 500})
        self.b.ok('materializer_apply', name='history', update=first)
        self.assertFalse(self.b.ok('materializer_read', name='history')['pending'])
        self.assertEqual(self.b.ok('materializer_read', name='history')['text'], 'AXZB')
        self.assertEqual(self.b.ok('materializer_state', name='history')['update'],
                         self.b.ok('state', name='a')['update'])

    def test_H03_rejection_quarantines_disposable_state_and_preserves_other_owners(self):
        seed = self.b.ok('seed', text='AB')['update']
        self.b.ok('new', name='editor', client=10, seed=seed)
        self.b.ok('edit', name='editor', index=1, insert='X')
        before = self.b.ok('state', name='editor')['update']
        self.materializer()
        invalid = base64.b64encode(b'unsupported native packet').decode()
        self.assertIn('error', self.b.request(op='materializer_apply', name='history',
                                             update=invalid))
        self.assertIn('error', self.b.request(op='materializer_read', name='history'))
        self.assertEqual(self.b.ok('state', name='editor')['update'], before)
        self.b.ok('undo', name='editor')
        self.assertEqual(self.b.ok('read', name='editor')['text'], 'AB')
        self.materializer()
        self.assertEqual(self.b.ok('materializer_read', name='history')['text'], 'AB')

    def test_H04_materializer_and_session_handles_cannot_alias(self):
        seed = self.b.ok('seed', text='AB')['update']
        self.b.ok('new', name='editor', client=10, seed=seed)
        self.assertIn('error', self.b.request(op='materializer_new', name='editor', seed=seed))
        self.materializer()
        self.assertIn('error', self.b.request(op='new', name='history', client=20, seed=seed))
        self.assertIn('error', self.b.request(op='edit', name='history', index=0, insert='x'))
        self.assertEqual(self.b.ok('read', name='editor')['text'], 'AB')

    def test_H05_incremental_history_has_no_session_undo_replay_budget(self):
        seed = self.b.ok('seed', text='AB')['update']
        self.b.ok('new', name='source', client=10, seed=seed)
        self.materializer(sessionBytes=1)
        for index in range(40):
            packet = self.b.ok('edit', name='source', index=1, insert='x')['update']
            self.b.ok('materializer_apply', name='history', update=packet)
        self.assertEqual(self.b.ok('materializer_state', name='history')['update'],
                         self.b.ok('state', name='source')['update'])

    def test_H06_private_save_packets_do_not_repeat_prior_generations_delete_sets(self):
        seed = self.b.ok('seed', text='AB')['update']
        self.b.ok('new', name='owner', client=10, seed=seed)
        self.b.ok('new', name='cold', client=20, seed=seed)
        sizes = []
        for generation in range(32):
            self.b.ok('draft', name='draft', source='owner', client=100 + generation)
            text = self.b.ok('read', name='draft')['text']
            self.b.ok('edit', name='draft', index=0, delete=len(text), insert='XYZ')
            saved = self.b.ok('save', name='draft', target='owner')['update']
            sizes.append(len(base64.b64decode(saved)))
            self.b.ok('apply', name='cold', update=saved)
        self.assertLessEqual(sizes[-1], sizes[0] + 48,
                             'A private Save must publish its own transactions, not historical deletes.')
        self.assertEqual(self.b.ok('state', name='cold')['update'],
                         self.b.ok('state', name='owner')['update'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
