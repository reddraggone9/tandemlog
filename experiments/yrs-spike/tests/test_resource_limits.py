"""Frozen before implementation: strict struct-author inspection and serialized resource budgets."""
import base64
import ctypes
import json
import unittest
import test_contract as contract
import test_admission as admission


class NativeBudgets(unittest.TestCase):
    setUp = contract.Contract.setUp
    seed = contract.Contract.seed
    pair = contract.Contract.pair
    edit = contract.Contract.edit
    text = contract.Contract.text
    full = contract.Contract.full
    apply = contract.Contract.apply
    draft = contract.Contract.draft

    def limits(self, **changes):
        value = dict(visibleUtf16=500, updateBytes=64, stateBytes=8192,
                     sessionBytes=16384, retainedBytes=65536)
        value.update(changes); return value

    def new(self, text='x', client=10, name='a', **limits):
        return self.b.ok('new', name=name, client=client, seed=self.seed(text), limits=self.limits(**limits))

    def usage(self, name='a'): return self.b.ok('usage', name=name)

    def test_B01_struct_actor_inspection_is_sorted_unique_and_readonly(self):
        self.pair('x'); ua = self.edit('a', 1, 'L'); ub = self.edit('b', 0, 'R'); self.apply('a', ub)
        before = self.full('a')
        self.assertEqual(self.b.ok('inspect', update=ua)['structActors'], [10])
        self.assertEqual(self.b.ok('inspect', update=ub)['structActors'], [20])
        self.assertEqual(self.b.ok('inspect', update=before)['structActors'], [1, 10, 20])
        self.assertEqual(self.full('a'), before)

    def test_B02_delete_references_and_skip_holes_are_not_struct_authors(self):
        self.pair('abc'); deleted = self.edit('a', 1, delete=1)
        self.assertEqual(self.b.ok('inspect', update=deleted)['structActors'], [])
        skip = bytes([1, 1, 50, 0, 10, 1, 0])
        self.assertEqual(self.b.ok('inspect', update=base64.b64encode(skip).decode())['structActors'], [])

    def test_B03_inspector_validates_binary_base64_and_plaintext_before_metadata(self):
        self.pair('safe'); before = self.full('a')
        for update in ['!!', '', base64.b64encode(b'garbage').decode(), admission.packet(root='evil'), admission.packet(info=5, content=admission.buf('embed'))]:
            result = self.b.request(op='inspect', update=update)
            self.assertIn('error', result); self.assertNotIn('structActors', result)
            self.assertEqual(self.full('a'), before)

    def test_B04_visible_utf16_limit_rejects_atomically_with_prior_undo(self):
        self.new('A😀', visibleUtf16=4); self.edit('a', 3, 'B'); before = self.full('a')
        result = self.b.request(op='edit', name='a', index=4, delete=0, insert='C')
        self.assertIn('error', result); self.assertEqual(self.full('a'), before)
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'A😀')

    def test_B05_generated_update_budget_is_distinct_from_visible_and_state(self):
        self.new(updateBytes=32); self.edit('a', 1, 'L'); before = self.full('a')
        result = self.b.request(op='edit', name='a', index=2, delete=0, insert='Z'*80)
        self.assertIn('error', result); self.assertEqual(self.full('a'), before)
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_B06_large_checkpoint_and_existing_history_do_not_use_operation_limit(self):
        self.new(updateBytes=32)
        for i in range(35): self.edit('a', i+1, 'abc')
        # Read current length; operation edits deliberately stay small.
        checkpoint = self.b.ok('checkpoint', name='a')['checkpoint']
        self.assertGreater(len(base64.b64decode(checkpoint['state'])), 32)
        self.b.ok('restore', name='restored', client=40, checkpoint=checkpoint, limits=self.limits(updateBytes=32))
        self.assertEqual(self.text('restored'), self.text('a'))
        self.edit('restored', 0, 'R'); self.assertTrue(self.text('restored').startswith('R'))
        self.b.ok('draft', name='draft', source='a', client=30)
        self.edit('draft', 0, 'D'); self.b.ok('save', name='draft', target='a')
        self.assertTrue(self.text('a').startswith('D'))

    def test_B07_state_limit_growth_rejection_retains_exact_live_state(self):
        self.new(stateBytes=80, updateBytes=64)
        rejected = False
        for _ in range(100):
            before = self.full('a'); result = self.b.request(op='edit', name='a', index=0, delete=0, insert='Q')
            if 'error' in result:
                self.assertEqual(self.full('a'), before); self.assertLessEqual(len(base64.b64decode(before)), 80)
                rejected = True; break
        self.assertTrue(rejected, 'encoded retained state must have a separate enforced cap')

    def test_B08_session_replay_limit_is_explicit_and_rejection_keeps_undo(self):
        self.new(sessionBytes=110)
        rejected = False
        for _ in range(30):
            before = self.full('a'); result = self.b.request(op='edit', name='a', index=0, delete=0, insert='Q')
            if 'error' in result:
                self.assertIn('budget', result['error']); self.assertEqual(self.full('a'), before)
                self.assertLessEqual(self.usage()['replayBytes'], 110); rejected = True; break
        self.assertTrue(rejected)
        self.b.ok('undo', name='a')

    def test_B09_prepared_clone_budget_rejection_keeps_original_session_undo(self):
        self.new(sessionBytes=50); self.edit('a', 1, 'L'); before = self.full('a')
        result = self.b.request(op='prepare_undo', name='a')
        self.assertIn('error', result); self.assertIn('budget', result['error']); self.assertEqual(self.full('a'), before)
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_B10_usage_documents_serialized_weights_and_actual_owner_guid(self):
        created = self.new(); read = self.b.ok('read', name='a'); usage = self.usage()
        self.assertEqual(created['guid'], read['guid']); self.assertEqual(usage['ownerGuid'], created['guid'])
        self.assertEqual(created['client'], 10); self.assertEqual(usage['stateBytes'], len(base64.b64decode(self.full('a'))))
        self.assertEqual(usage['limits'], self.limits()); self.assertEqual(usage['accounting'], 'serialized-payload-bytes-not-native-rss')
        self.assertGreater(usage['retainedBytes'], usage['stateBytes'])

    def test_B11_retained_receipt_history_is_bounded_without_pruning(self):
        self.new(retainedBytes=600); self.edit('a', 1, 'L'); p = self.b.ok('prepare_undo', name='a')
        receipt = {'update': p['update']}; first = self.b.ok('commit_undo', name='a', token=p['token'], receipt=receipt)
        rejected = False
        for _ in range(30):
            before = self.full('a'); redo = self.b.request(op='redo', name='a')
            if 'error' in redo:
                self.assertEqual(self.full('a'), before); rejected = True; break
            before = self.full('a'); prepared = self.b.request(op='prepare_undo', name='a')
            if 'error' in prepared:
                self.assertEqual(self.full('a'), before); rejected = True; break
            before = self.full('a'); result = self.b.request(op='commit_undo', name='a', token=prepared['token'], receipt={'update': prepared['update']})
            if 'error' in result:
                self.assertEqual(self.full('a'), before); self.b.ok('cancel_prepared_undo', name='a', token=prepared['token']); rejected = True; break
        self.assertTrue(rejected); self.assertLessEqual(self.usage()['retainedBytes'], 600)
        self.assertEqual(self.b.ok('commit_undo', name='a', token=p['token'], receipt=receipt), first)

    def test_B12_restore_limit_failure_does_not_replace_existing_owner(self):
        self.pair('safe'); before = self.full('a'); checkpoint = self.b.ok('checkpoint', name='a')['checkpoint']
        result = self.b.request(op='restore', name='a', client=40, checkpoint=checkpoint, limits=self.limits(stateBytes=2))
        self.assertIn('error', result); self.assertEqual(self.full('a'), before)
        result = self.b.request(op='restore', name='missing', client=40, checkpoint=checkpoint, limits=self.limits(stateBytes=2))
        self.assertIn('error', result); self.assertIn('error', self.b.request(op='read', name='missing'))

    def test_B13_private_draft_inherits_limits_and_rejection_preserves_draft(self):
        self.new(visibleUtf16=3); self.draft(); self.edit('draft', 1, 'L'); before = self.full('draft')
        result = self.b.request(op='edit', name='draft', index=2, delete=0, insert='ZZ')
        self.assertIn('error', result); self.assertEqual(self.full('draft'), before); self.assertEqual(self.text('a'), 'x')
        self.b.ok('save', name='draft', target='a'); self.assertEqual(self.text('a'), 'xL')

    def test_B14_limit_configuration_rejects_unknown_zero_boolean_and_overflow(self):
        for limits in [dict(unknown=1), dict(visibleUtf16=0), dict(updateBytes=True), dict(stateBytes=-1), dict(stateBytes=2**63)]:
            result = self.b.request(op='new', name='bad', client=10, seed=self.seed('x'), limits=limits)
            self.assertIn('error', result); self.assertIn('error', self.b.request(op='read', name='bad'))

    def test_B15_large_bounded_checkpoint_frame_and_input_allocator(self):
        state = admission.packet(client=1, content=admission.buf('a'*230000))
        request = json.dumps(dict(op='new', name='large', client=10, seed=state,
                            limits=self.limits(visibleUtf16=250000, stateBytes=1048576, sessionBytes=2097152, retainedBytes=4194304))).encode()+b'\x00'
        self.assertGreater(len(request), 300001)
        lib = self.b.lib; lib.tandemlog_text_alloc.argtypes = [ctypes.c_size_t]; lib.tandemlog_text_alloc.restype = ctypes.c_void_p
        lib.tandemlog_text_release_input.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        ptr = lib.tandemlog_text_alloc(len(request)); self.assertTrue(ptr)
        try:
            ctypes.memmove(ptr, request, len(request)); response = lib.spike_json(ctypes.cast(ptr, ctypes.c_char_p))
            try: value = json.loads(ctypes.string_at(response)); self.assertNotIn('error', value)
            finally: lib.spike_free(response)
        finally: lib.tandemlog_text_release_input(ptr, len(request))
        self.assertEqual(len(self.text('large')), 230000)
        checkpoint = self.b.ok('checkpoint', name='large')['checkpoint']
        self.b.ok('restore', name='restored', client=40, checkpoint=checkpoint,
                  limits=self.limits(visibleUtf16=250000, stateBytes=1048576, sessionBytes=2097152, retainedBytes=4194304))
        self.assertEqual(self.text('restored'), self.text('large'))


if __name__ == '__main__': unittest.main(verbosity=2)
