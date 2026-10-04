"""Frozen before worker implementation; real caller OS threads share one native owner."""
import concurrent.futures
import ctypes
import json
import threading
import unittest
import test_contract as contract


class WorkerOwnership(unittest.TestCase):
    setUp = contract.Contract.setUp
    seed = contract.Contract.seed
    pair = contract.Contract.pair
    edit = contract.Contract.edit
    text = contract.Contract.text
    full = contract.Contract.full
    apply = contract.Contract.apply
    draft = contract.Contract.draft

    def on_thread(self, call):
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            return pool.submit(call).result(timeout=10)

    def aliases(self):
        lib = self.b.lib
        lib.tandemlog_text_json.argtypes = [ctypes.c_char_p]
        lib.tandemlog_text_json.restype = ctypes.c_void_p
        for name in ['tandemlog_text_free', 'spike_free']:
            getattr(lib, name).argtypes = [ctypes.c_void_p]
            getattr(lib, name).restype = None
        for name in ['tandemlog_text_alloc', 'spike_alloc']:
            getattr(lib, name).argtypes = [ctypes.c_size_t]
            getattr(lib, name).restype = ctypes.c_void_p
        for name in ['tandemlog_text_release_input', 'spike_release_input']:
            getattr(lib, name).argtypes = [ctypes.c_void_p, ctypes.c_size_t]
            getattr(lib, name).restype = None
        return lib

    def test_W01_same_handle_is_shared_across_different_caller_threads(self):
        self.pair('x')
        self.assertEqual(self.on_thread(lambda: self.text('a')), 'x')
        update = self.on_thread(lambda: self.edit('a', 1, 'L'))
        self.apply('b', update); self.assertEqual(self.text('a'), 'xL')
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            ids = list(pool.map(lambda _: (threading.get_ident(), self.text('a')), range(30)))
        self.assertTrue(all(value == 'xL' for _, value in ids))

    def test_W02_production_and_spike_json_aliases_share_exact_owner(self):
        self.pair('x'); lib = self.aliases()
        def read():
            ptr = lib.tandemlog_text_json(b'{"op":"read","name":"a"}')
            try: return json.loads(ctypes.string_at(ptr))
            finally: lib.spike_free(ptr)
        self.assertEqual(self.on_thread(read)['text'], 'x')
        self.edit('a', 1, 'L'); self.assertEqual(read()['text'], 'xL')

    def test_W03_concurrent_remote_prepare_and_receipt_commit_converge(self):
        seed = self.pair('x'); local = self.edit('a', 1, 'L')
        self.b.ok('new', name='c', client=30, seed=seed)
        updates = [self.edit('b', 0, 'B'), self.edit('c', 0, 'C')]
        barrier = threading.Barrier(3)
        def remote(update): barrier.wait(); return self.apply('a', update)
        def prepare(): barrier.wait(); return self.b.ok('prepare_undo', name='a')
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            results = [pool.submit(remote, update) for update in updates]
            pending = pool.submit(prepare)
            for future in results: future.result(timeout=10)
            prepared = pending.result(timeout=10)
        self.on_thread(lambda: self.b.ok('commit_undo', name='a', token=prepared['token'], receipt={'update': prepared['update']}))
        self.b.ok('new', name='reference', client=40, seed=seed)
        for update in [local, *updates, prepared['update']]: self.apply('reference', update)
        self.assertEqual(self.text('a'), self.text('reference'))
        self.assertIn('B', self.text('a')); self.assertIn('C', self.text('a')); self.assertNotIn('L', self.text('a'))

    def test_W04_simultaneous_prepare_returns_one_immutable_owner_token(self):
        self.pair('x'); self.edit('a', 1, 'L'); before = self.full('a'); barrier = threading.Barrier(8)
        def prepare(_): barrier.wait(); return self.b.ok('prepare_undo', name='a')
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            prepared = list(pool.map(prepare, range(8)))
        self.assertTrue(all(item == prepared[0] for item in prepared)); self.assertEqual(self.full('a'), before)
        self.on_thread(lambda: self.b.ok('cancel_prepared_undo', name='a', token=prepared[0]['token']))
        self.on_thread(lambda: self.b.ok('undo', name='a')); self.assertEqual(self.text('a'), 'x')

    def test_W05_wrong_receipt_and_cross_thread_cancel_preserve_prior_undo(self):
        self.pair('x'); self.edit('a', 1, 'L')
        p = self.on_thread(lambda: self.b.ok('prepare_undo', name='a')); before = self.full('a')
        error = self.on_thread(lambda: self.b.request(op='commit_undo', name='a', token=p['token'], receipt={'update': self.seed('wrong')}))
        self.assertIn('error', error); self.assertEqual(self.full('a'), before)
        self.on_thread(lambda: self.b.ok('cancel_prepared_undo', name='a', token=p['token']))
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_W06_response_callback_buffer_can_be_read_and_freed_elsewhere(self):
        self.pair('😀日本'); lib = self.aliases()
        for _ in range(40):
            ptr = self.on_thread(lambda: lib.tandemlog_text_json(b'{"op":"read","name":"a"}'))
            self.assertTrue(ptr)
            def callback():
                try: return json.loads(ctypes.string_at(ptr))
                finally: lib.tandemlog_text_free(ptr)
            self.assertEqual(self.on_thread(callback)['text'], '😀日本')

    def test_W07_late_cross_thread_receipt_cannot_attach_to_recreated_name(self):
        self.pair('x'); self.edit('a', 1, 'L'); p = self.on_thread(lambda: self.b.ok('prepare_undo', name='a'))
        self.on_thread(lambda: self.b.ok('cancel', name='a'))
        self.on_thread(lambda: self.b.ok('new', name='a', client=30, seed=self.seed('new')))
        result = self.on_thread(lambda: self.b.request(op='commit_undo', name='a', token=p['token'], receipt={'update': p['update']}))
        self.assertIn('error', result); self.assertEqual(self.text('a'), 'new')

    def test_W08_invalid_request_error_does_not_reset_or_reseed_owner(self):
        self.pair('x'); self.edit('a', 1, 'L'); before = self.full('a'); lib = self.b.lib
        def invalid():
            ptr = lib.spike_json(b'{broken')
            try: return json.loads(ctypes.string_at(ptr))
            finally: lib.spike_free(ptr)
        self.assertEqual(self.on_thread(invalid)['error'], 'invalid JSON')
        self.assertEqual(self.full('a'), before); self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_W09_private_draft_preparation_has_specific_ownership_rejection(self):
        self.pair('x'); self.draft(); self.edit('draft', 1, 'L'); before = self.full('draft')
        result = self.on_thread(lambda: self.b.request(op='prepare_undo', name='draft'))
        self.assertEqual(result.get('error'), 'private draft Undo is not a durable preparation')
        self.assertEqual(self.full('draft'), before); self.assertEqual(self.text('a'), 'x')

    def test_W10_captured_draft_guid_survives_cross_thread_receipt_commit(self):
        self.pair('x'); self.edit('a', 1, 'L'); self.draft(); self.edit('draft', 2, 'D')
        p = self.on_thread(lambda: self.b.ok('prepare_undo', name='a'))
        self.on_thread(lambda: self.b.ok('commit_undo', name='a', token=p['token'], receipt={'update': p['update']}))
        self.on_thread(lambda: self.b.ok('save', name='draft', target='a'))
        self.assertEqual(self.text('a'), 'xD')

    def test_W11_input_allocation_and_release_aliases_share_allocator(self):
        self.pair('x'); lib = self.aliases(); request = b'{"op":"read","name":"a"}\x00'
        for alloc, release in [(lib.spike_alloc, lib.tandemlog_text_release_input), (lib.tandemlog_text_alloc, lib.spike_release_input)]:
            ptr = self.on_thread(lambda: alloc(len(request))); self.assertTrue(ptr)
            ctypes.memmove(ptr, request, len(request))
            response = self.on_thread(lambda: lib.tandemlog_text_json(ctypes.cast(ptr, ctypes.c_char_p)))
            self.on_thread(lambda: release(ptr, len(request)))
            try: self.assertEqual(json.loads(ctypes.string_at(response))['text'], 'x')
            finally: self.on_thread(lambda: lib.spike_free(response))


if __name__ == '__main__': unittest.main(verbosity=2)
