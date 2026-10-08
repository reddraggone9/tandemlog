"""Frozen before native implementation: receipt-gated selective Undo preparation."""
import base64
import unittest
import test_contract as contract


class PreparedUndo(unittest.TestCase):
    setUp = contract.Contract.setUp
    seed = contract.Contract.seed
    pair = contract.Contract.pair
    text = contract.Contract.text
    full = contract.Contract.full
    edit = contract.Contract.edit
    apply = contract.Contract.apply
    draft = contract.Contract.draft

    def prepare(self, name='a'):
        return self.b.ok('prepare_undo', name=name)

    def commit(self, prepared, name='a', **extra):
        return self.b.ok('commit_undo', name=name, token=prepared['token'],
                         receipt={'update': prepared['update']}, **extra)

    def test_U01_prepare_is_nonmutating_and_repeated_bytes_are_immutable(self):
        self.pair('abc'); self.edit('a', 1, delete=1)
        before = self.full('a')
        p = self.prepare(); repeated = self.prepare()
        self.assertTrue(p['changed']); self.assertEqual(p, repeated)
        self.assertEqual(self.full('a'), before); self.assertEqual(self.text('a'), 'ac')
        self.assertTrue(base64.b64decode(p['update']))
        self.commit(p); self.assertEqual(self.text('a'), 'abc')

    def test_U02_missing_wrong_receipt_does_not_change_live_or_consume_undo(self):
        self.pair('x'); self.edit('a', 1, 'L'); before = self.full('a'); p = self.prepare()
        for receipt in [None, {}, {'update': self.seed('wrong')}, {'update': '!!'}]:
            r = self.b.request(op='commit_undo', name='a', token=p['token'], receipt=receipt)
            self.assertIn('error', r); self.assertEqual(self.full('a'), before)
            self.assertEqual(self.prepare(), p)
        self.commit(p); self.assertEqual(self.text('a'), 'x')

    def test_U03_remote_arrival_after_prepare_preserves_exact_compensation(self):
        self.pair('abc'); local = self.edit('a', 1, delete=1); self.apply('b', local)
        p = self.prepare(); remote = self.edit('b', 1, 'REMOTE'); self.apply('a', remote)
        self.assertEqual(self.prepare(), p); self.assertIn('REMOTE', self.text('a'))
        self.commit(p); self.apply('b', p['update'])
        self.assertEqual(self.text('a'), self.text('b'))
        self.assertIn('REMOTE', self.text('a')); self.assertIn('b', self.text('a'))

    def test_U04_unknown_receipt_retry_is_idempotent_and_keeps_prior_undo(self):
        self.pair('x'); self.edit('a', 1, 'ONE'); self.edit('a', 4, 'TWO')
        p = self.prepare(); first = self.commit(p); before = self.full('a')
        self.assertEqual(self.commit(p), first); self.assertEqual(self.full('a'), before)
        self.assertEqual(self.text('a'), 'xONE')
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_U05_cancel_and_rejection_preserve_prior_selective_undo(self):
        self.pair('x'); self.edit('a', 1, 'L'); p = self.prepare(); before = self.full('a')
        self.b.ok('cancel_prepared_undo', name='a', token=p['token'])
        self.assertEqual(self.full('a'), before)
        self.assertIn('error', self.b.request(op='commit_undo', name='a', token=p['token'], receipt={'update': p['update']}))
        q = self.prepare(); self.assertNotEqual(q['token'], p['token']); self.assertEqual(q['update'], p['update'])
        self.b.ok('cancel_prepared_undo', name='a', token=q['token'])
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_U06_pending_blocks_local_changes_but_accepts_remote(self):
        self.pair('x'); self.edit('a', 1, 'L'); p = self.prepare(); before = self.full('a')
        for op in ['edit', 'undo', 'redo', 'apply_local']:
            r = self.b.request(op=op, name='a', index=0, delete=0, insert='BAD', update=self.seed('bad'))
            self.assertIn('error', r); self.assertEqual(self.full('a'), before)
        self.apply('a', self.edit('b', 0, 'R')); self.commit(p)
        self.assertEqual(self.text('a'), 'Rx')

    def test_U07_token_bound_to_owner_and_not_reused_name(self):
        self.pair('x'); self.edit('a', 1, 'L'); p = self.prepare(); before = self.full('b')
        self.assertIn('error', self.b.request(op='commit_undo', name='b', token=p['token'], receipt={'update': p['update']}))
        self.assertEqual(self.full('b'), before)
        self.b.ok('cancel', name='a'); self.b.ok('new', name='a', client=30, seed=self.seed('new'))
        self.assertIn('error', self.b.request(op='commit_undo', name='a', token=p['token'], receipt={'update': p['update']}))
        self.assertEqual(self.text('a'), 'new')

    def test_U08_captured_draft_identity_survives_clone_commit_and_remote(self):
        self.pair('x'); local = self.edit('a', 1, 'L'); self.apply('b', local)
        self.draft(); self.edit('draft', 2, 'D'); p = self.prepare()
        self.apply('a', self.edit('b', 0, 'R')); self.commit(p)
        prepared_draft = self.b.ok('prepare', name='draft', target='a')
        self.b.ok('apply_local', name='a', update=prepared_draft['update'])
        self.assertEqual(self.text('a'), 'RxD')

    def test_U09_saved_draft_batch_undo_and_redo_ownership_are_preserved(self):
        self.pair('x'); self.draft(); self.edit('draft', 1, 'ONE'); self.edit('draft', 4, 'TWO')
        self.b.ok('save', name='draft', target='a'); self.apply('a', self.edit('b', 0, 'R'))
        p = self.prepare(); self.commit(p); self.assertEqual(self.text('a'), 'Rx')
        self.b.ok('redo', name='a'); self.assertEqual(self.text('a'), 'RxONETWO')
        q = self.prepare(); self.commit(q); self.assertEqual(self.text('a'), 'Rx')

    def test_U10_immutable_compensation_replays_after_native_reset(self):
        seed = self.pair('abc'); original = self.edit('a', 1, 'L'); p = self.prepare()
        self.b.ok('reset'); self.b.ok('new', name='fresh', client=40, seed=seed)
        self.apply('fresh', p['update']); self.assertTrue(self.b.ok('read', name='fresh')['pending'])
        self.apply('fresh', original); self.assertEqual(self.text('fresh'), 'abc')
        self.apply('fresh', p['update']); self.assertEqual(self.text('fresh'), 'abc')

    def test_U11_no_undo_rejection_and_anchor_lifetime(self):
        self.pair('abc'); before = self.full('a')
        self.assertIn('error', self.b.request(op='prepare_undo', name='a'))
        self.assertEqual(self.full('a'), before)
        self.edit('a', 0, 'L'); self.b.ok('anchor', name='a', index=3)
        p = self.prepare(); self.apply('a', self.edit('b', 0, 'R')); self.commit(p)
        self.assertEqual(self.b.ok('anchor_read', name='a')['index'], 3)

    def test_U12_failed_prepare_draft_keeps_target_and_private_undo(self):
        self.pair('x'); self.draft(); self.edit('draft', 1, 'L'); before = self.full('draft')
        self.assertIn('error', self.b.request(op='prepare_undo', name='draft'))
        self.assertEqual(self.full('draft'), before); self.assertEqual(self.text('a'), 'x')
        self.b.ok('undo', name='draft'); self.assertEqual(self.text('draft'), 'x')


if __name__ == '__main__': unittest.main(verbosity=2)
