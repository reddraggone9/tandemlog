"""Acceptance cases frozen BEFORE the isolated prototype implementation.

Native bridge ABI: spike_json(UTF-8 JSON request) -> allocated JSON response;
spike_free(response). Only disposable synthetic data is used.
"""
import base64
import ctypes
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = Path(os.environ.get('SPIKE_LIBRARY', ROOT / 'target/release/libtandemlog_yrs_spike.so'))


class Bridge:
    def __init__(self):
        self.lib = ctypes.CDLL(str(LIB))
        self.lib.spike_json.argtypes = [ctypes.c_char_p]
        self.lib.spike_json.restype = ctypes.c_void_p
        self.lib.spike_free.argtypes = [ctypes.c_void_p]

    def request(self, **value):
        p = self.lib.spike_json(json.dumps(value, ensure_ascii=False).encode())
        if not p:
            raise AssertionError('native bridge returned null')
        try:
            return json.loads(ctypes.string_at(p))
        finally:
            self.lib.spike_free(p)

    def ok(self, op, **value):
        r = self.request(op=op, **value)
        if 'error' in r:
            raise AssertionError(r['error'])
        return r


class Contract(unittest.TestCase):
    def setUp(self):
        self.b = Bridge()
        self.b.ok('reset')

    def seed(self, text='Buy oats'):
        return self.b.ok('seed', text=text)['update']

    def pair(self, text='Buy oats'):
        seed = self.seed(text)
        for name, client in [('a', 10), ('b', 20)]:
            self.b.ok('new', name=name, client=client, seed=seed)
        return seed

    def text(self, name):
        return self.b.ok('read', name=name)['text']

    def edit(self, name, index, insert='', delete=0):
        return self.b.ok('edit', name=name, index=index, insert=insert, delete=delete)['update']

    def apply(self, name, update):
        return self.b.ok('apply', name=name, update=update)

    def full(self, name):
        return self.b.ok('state', name=name)['update']

    def draft(self, name='draft', source='a', client=30):
        return self.b.ok('draft', name=name, source=source, client=client)

    def test_C01_shared_seed_does_not_duplicate_historical_text(self):
        self.pair()
        self.apply('a', self.full('b'))
        self.apply('b', self.full('a'))
        self.assertEqual(self.text('a'), 'Buy oats')
        self.assertEqual(self.text('a'), self.text('b'))

    def test_C02_save_publishes_only_draft_changes(self):
        self.pair()
        self.draft()
        self.edit('draft', 8, ' and fruit')
        self.assertEqual(self.text('a'), 'Buy oats')
        saved = self.b.ok('save', name='draft', target='a')['update']
        self.apply('b', saved)
        self.assertEqual(self.text('b'), 'Buy oats and fruit')

    def test_C03_cancel_has_no_published_change(self):
        self.pair()
        before = self.full('a')
        self.draft()
        self.edit('draft', 0, 'Discarded ')
        self.b.ok('cancel', name='draft')
        self.assertEqual(before, self.full('a'))

    def test_C04_save_captured_baseline_preserves_remote_insert(self):
        self.pair()
        self.draft()
        self.edit('draft', 8, ' and fruit')
        self.apply('a', self.edit('b', 0, 'Urgent: '))
        self.b.ok('save', name='draft', target='a')
        self.assertEqual(self.text('a'), 'Urgent: Buy oats and fruit')

    def test_C05_draft_delete_does_not_delete_concurrent_insert(self):
        self.pair('abcd')
        self.draft()
        self.edit('draft', 1, delete=2)
        self.apply('a', self.edit('b', 2, 'REMOTE'))
        self.b.ok('save', name='draft', target='a')
        self.assertIn('REMOTE', self.text('a'))
        self.assertNotIn('b', self.text('a'))
        self.assertNotIn('c', self.text('a'))

    def test_C06_offline_disjoint_insertions_merge(self):
        self.pair()
        ua = self.edit('a', 8, ' and fruit')
        ub = self.edit('b', 0, 'Urgent: ')
        self.apply('a', ub); self.apply('b', ua)
        self.assertEqual(self.text('a'), 'Urgent: Buy oats and fruit')
        self.assertEqual(self.text('a'), self.text('b'))

    def test_C07_same_location_insertions_converge_without_lost_text(self):
        self.pair('xy')
        ua = self.edit('a', 1, 'AAA')
        ub = self.edit('b', 1, 'BBB')
        self.apply('a', ub); self.apply('b', ua)
        self.assertEqual(self.text('a'), self.text('b'))
        for part in ('AAA', 'BBB', 'x', 'y'):
            self.assertIn(part, self.text('a'))

    def test_C08_concurrent_overlapping_deletes_converge(self):
        self.pair('abcdef')
        ua = self.edit('a', 1, delete=3)
        ub = self.edit('b', 2, delete=3)
        self.apply('a', ub); self.apply('b', ua)
        self.assertEqual(self.text('a'), 'af')
        self.assertEqual(self.text('b'), 'af')

    def test_C09_duplicate_delivery_is_idempotent(self):
        self.pair()
        update = self.edit('a', 8, ' more')
        for _ in range(20): self.apply('b', update)
        self.assertEqual(self.text('b'), 'Buy oats more')

    def test_C10_out_of_order_missing_dependency_eventually_integrates(self):
        self.pair('x')
        first = self.edit('a', 1, 'A')
        second = self.edit('a', 2, 'B')
        r = self.apply('b', second)
        self.assertTrue(r['pending'])
        self.assertEqual(self.text('b'), 'x')
        self.apply('b', first)
        self.assertEqual(self.text('b'), 'xAB')
        self.assertFalse(self.b.ok('read', name='b')['pending'])

    def test_C11_pending_dependency_survives_checkpoint_restart(self):
        self.pair('x')
        first = self.edit('a', 1, 'A')
        second = self.edit('a', 2, 'B')
        self.apply('b', second)
        checkpoint = self.b.ok('checkpoint', name='b')['checkpoint']
        self.b.ok('cancel', name='b')
        self.b.ok('restore', name='c', client=40, checkpoint=checkpoint)
        self.apply('c', first)
        self.assertEqual(self.text('c'), 'xAB')

    def test_C12_all_delivery_permutations_converge(self):
        seed = self.pair('x')
        updates = [self.edit('a', 1, 'A'), self.edit('a', 2, 'B'), self.edit('b', 0, 'Q')]
        for i, order in enumerate(itertools.permutations(updates)):
            name = f'p{i}'
            self.b.ok('new', name=name, client=100+i, seed=seed)
            for update in order: self.apply(name, update)
            self.assertEqual(self.text(name), 'QxAB')

    def test_C13_random_duplicate_out_of_order_delivery(self):
        seed = self.pair('seed')
        updates = []
        for i in range(30):
            updates.append(self.edit('a', 4+i, str(i % 10)))
            updates.append(self.edit('b', i, 'Z'))
        expected = None
        for trial in range(12):
            name = f'p{trial}'
            self.b.ok('new', name=name, client=100+trial, seed=seed)
            mixed = updates * 2
            random.Random(trial).shuffle(mixed)
            for update in mixed: self.apply(name, update)
            value = self.text(name)
            expected = value if expected is None else expected
            self.assertEqual(value, expected)
            self.assertFalse(self.b.ok('read', name=name)['pending'])

    def test_C14_independent_fields_remain_independent(self):
        self.pair('Title')
        self.b.ok('new', name='notes', client=30, seed=self.seed('Notes'))
        self.edit('a', 5, '!')
        self.assertEqual(self.text('notes'), 'Notes')

    def test_C15_recurrence_successor_text_is_independent(self):
        self.pair('Recurring')
        self.b.ok('new', name='successor', client=30, seed=self.seed(self.text('a')))
        self.edit('a', 0, 'Historical ')
        self.assertEqual(self.text('successor'), 'Recurring')

    def test_C16_unicode_utf16_offsets_and_emoji(self):
        self.pair('A😀B')
        update = self.edit('a', 3, 'é日本')
        self.apply('b', update)
        self.assertEqual(self.text('b'), 'A😀é日本B')
        self.edit('a', 1, delete=2)
        self.assertEqual(self.text('a'), 'Aé日本B')

    def test_C17_split_surrogate_offsets_rejected_without_mutation(self):
        self.pair('A😀B')
        before = self.full('a')
        for index, delete in [(2, 0), (1, 1), (0, 2)]:
            r = self.b.request(op='edit', name='a', index=index, delete=delete, insert='X')
            self.assertIn('error', r)
            self.assertEqual(self.full('a'), before)

    def test_C18_combining_zwj_and_markdown_remain_source_text(self):
        source = '# Heading\n- [link](https://example.com)\nCafe\u0301 👩\u200d💻'
        self.pair(source)
        self.apply('b', self.edit('a', 0, 'Prefix '))
        self.assertEqual(self.text('b'), 'Prefix '+source)

    def test_C19_composition_blocks_save_and_cancel_discards(self):
        self.pair('Draft')
        self.draft()
        self.b.ok('composition', name='draft', active=True)
        self.edit('draft', 5, 'に')
        self.assertIn('error', self.b.request(op='save', name='draft', target='a'))
        self.assertEqual(self.text('a'), 'Draft')
        self.b.ok('cancel', name='draft')
        self.assertEqual(self.text('a'), 'Draft')

    def test_C20_composition_commit_publishes_final_text_once(self):
        self.pair('Draft')
        self.draft()
        self.b.ok('composition', name='draft', active=True)
        self.edit('draft', 5, 'に')
        self.edit('draft', 5, '日本', delete=1)
        self.b.ok('composition', name='draft', active=False)
        update = self.b.ok('save', name='draft', target='a')['update']
        self.apply('b', update); self.apply('b', update)
        self.assertEqual(self.text('b'), 'Draft日本')

    def test_C21_sticky_selection_moves_with_remote_prefix(self):
        self.pair('abc')
        self.b.ok('anchor', name='a', index=2)
        self.apply('a', self.edit('b', 0, 'XX'))
        self.assertEqual(self.b.ok('anchor_read', name='a')['index'], 4)

    def test_C22_selective_undo_preserves_remote_insert(self):
        self.pair('x')
        local = self.edit('a', 1, 'LOCAL')
        remote = self.edit('b', 0, 'REMOTE')
        self.apply('a', remote); self.apply('b', local)
        undo = self.b.ok('undo', name='a')['update']
        self.apply('b', undo)
        self.assertEqual(self.text('a'), 'REMOTEx')
        self.assertEqual(self.text('b'), self.text('a'))

    def test_C23_selective_undo_save_batch_retains_remote(self):
        self.pair('x')
        self.draft()
        self.edit('draft', 1, 'ONE'); self.edit('draft', 4, 'TWO')
        self.apply('a', self.edit('b', 0, 'REMOTE'))
        self.b.ok('save', name='draft', target='a')
        self.b.ok('undo', name='a')
        self.assertEqual(self.text('a'), 'REMOTEx')

    def test_C24_redo_is_compensation_not_history_removal(self):
        self.pair('x')
        original = self.edit('a', 1, 'L')
        undo = self.b.ok('undo', name='a')['update']
        redo = self.b.ok('redo', name='a')['update']
        for update in (original, undo, redo): self.apply('b', update)
        self.assertEqual(self.text('b'), 'xL')
        self.assertEqual(len({original, undo, redo}), 3)

    def test_C25_undo_after_remote_delete_does_not_resurrect_remote_work(self):
        self.pair('abc')
        self.apply('b', self.edit('a', 1, 'L'))
        self.apply('a', self.edit('b', 1, delete=1))
        self.b.ok('undo', name='a')
        self.assertEqual(self.text('a'), 'abc')

    def test_C26_invalid_binary_rejected_atomically(self):
        self.pair('safe')
        before = self.full('a')
        for data in (b'', b'\xff', b'\x01', b'garbage'):
            r = self.b.request(op='apply', name='a', update=base64.b64encode(data).decode())
            self.assertIn('error', r)
            self.assertEqual(self.full('a'), before)

    def test_C27_oversized_update_rejected_before_decode(self):
        self.pair('safe')
        r = self.b.request(op='apply', name='a', update=base64.b64encode(b'x'*65537).decode())
        self.assertIn('error', r)
        self.assertEqual(self.text('a'), 'safe')

    def test_C28_out_of_range_edit_and_invalid_base64_are_atomic(self):
        self.pair('safe')
        for value in [{'op':'edit','index':99,'insert':'x','delete':0}, {'op':'edit','index':0,'insert':'x','delete':99}, {'op':'apply','update':'!!'}]:
            self.assertIn('error', self.b.request(name='a', **value))
            self.assertEqual(self.text('a'), 'safe')

    def test_C29_actor_collision_rejected(self):
        self.pair()
        self.assertIn('error', self.b.request(op='new', name='collision', client=10, seed=self.seed()))

    def test_C30_text_limit_rejected_without_partial_commit(self):
        self.pair('safe')
        self.assertIn('error', self.b.request(op='edit', name='a', index=0, insert='x'*65537, delete=0))
        self.assertEqual(self.text('a'), 'safe')

    def test_C31_exact_update_bytes_survive_json_roundtrip_and_replay(self):
        seed = self.pair('base')
        updates = [self.edit('a', 4, '1'), self.edit('b', 0, '2')]
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)/'synthetic.jsonl'
            records = [{'schema':1,'codec':'yrs-v1','update':u} for u in updates]
            p.write_text(''.join(json.dumps(r,sort_keys=True)+'\n' for r in records))
            before = hashlib.sha256(p.read_bytes()).hexdigest()
            self.b.ok('new', name='replay', client=40, seed=seed)
            for line in p.read_text().splitlines(): self.apply('replay', json.loads(line)['update'])
            self.assertEqual(self.text('replay'), '2base1')
            self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(), before)

    def test_C32_full_checkpoint_and_tail_equal_full_replay(self):
        self.pair('x')
        for _ in range(100): self.edit('a', 1, 'a')
        checkpoint = self.b.ok('checkpoint', name='a')['checkpoint']
        tail = self.edit('a', 0, 'TAIL')
        self.b.ok('restore', name='restored', client=40, checkpoint=checkpoint)
        self.apply('restored', tail)
        self.assertEqual(self.text('restored'), self.text('a'))
        self.assertFalse(self.b.ok('read', name='restored')['pending'])

    def test_C33_bridge_utf8_memory_cycles(self):
        self.pair('😀\u0000日本')
        for _ in range(1000): self.assertEqual(self.text('a'), '😀\u0000日本')

    def test_C34_performance_and_storage_measurements(self):
        self.pair('Notes')
        updates=[]; start=time.perf_counter()
        for i in range(2000): updates.append(self.edit('a', 5+i, 'a'))
        edit_ms=(time.perf_counter()-start)*1000
        checkpoint=self.b.ok('checkpoint', name='a')['checkpoint']
        start=time.perf_counter(); self.b.ok('restore', name='restored', client=40, checkpoint=checkpoint)
        restore_ms=(time.perf_counter()-start)*1000
        self.assertEqual(self.text('restored'), self.text('a'))
        report={'edits':2000,'utf16_length':2005,'edit_and_ffi_ms':edit_ms,'checkpoint_restore_and_ffi_ms':restore_ms,'raw_update_bytes':sum(len(base64.b64decode(u)) for u in updates),'checkpoint_json_bytes':len(json.dumps(checkpoint).encode()),'checkpoint_engine_bytes':len(base64.b64decode(checkpoint['state']))}
        (ROOT/'evidence').mkdir(exist_ok=True)
        (ROOT/'evidence/performance.json').write_text(json.dumps(report,indent=2)+'\n')
        self.assertLess(restore_ms, 1000, 'bounded synthetic checkpoint restore target')


if __name__ == '__main__': unittest.main(verbosity=2)
