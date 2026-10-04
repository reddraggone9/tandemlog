"""Admission regressions frozen and run red before adapter hardening.

Synthetic Yrs-v1 packets only. The upstream engine deliberately accepts generic
shared types; this adapter's contract admits one plain-text root, not rich text.
"""
import base64
import unittest
import test_contract as contract


def var(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128)
        n >>= 7
    out.append(n)
    return bytes(out)


def buf(value):
    data = value.encode()
    return var(len(data)) + data


def packet(info=4, content=None, root='text', client=50, clock=0, parent=None):
    # One struct, one client, zero deletes; same V1 format emitted by Yrs.
    prefix = var(1) + var(1) + var(client) + var(clock) + bytes([info])
    if parent is not None:
        prefix += var(0) + var(parent[0]) + var(parent[1])
    else:
        prefix += var(1) + buf(root)
    return base64.b64encode(prefix + (content or buf('HIDDEN')) + var(0)).decode()


class Admission(unittest.TestCase):
    setUp = contract.Contract.setUp
    pair = contract.Contract.pair
    seed = contract.Contract.seed
    edit = contract.Contract.edit
    full = contract.Contract.full
    text = contract.Contract.text
    apply = contract.Contract.apply

    def reject_unchanged(self, update):
        before = self.full('a')
        result = self.b.request(op='apply', name='a', update=update)
        self.assertIn('error', result)
        self.assertEqual(self.full('a'), before)
        self.assertEqual(self.text('a'), 'safe')

    def test_R01_foreign_root_apply_is_atomic(self):
        self.pair('safe')
        self.reject_unchanged(packet(root='evil'))

    def test_R02_foreign_root_cannot_enter_new(self):
        self.assertIn('error', self.b.request(op='new', name='a', client=10, seed=packet(root='evil')))
        self.assertIn('error', self.b.request(op='read', name='a'))

    def test_R03_foreign_root_cannot_enter_restore(self):
        checkpoint = {'schema': 1, 'codec': 'yrs-v1', 'state': packet(root='evil')}
        self.assertIn('error', self.b.request(op='restore', name='a', client=10, checkpoint=checkpoint))
        self.assertIn('error', self.b.request(op='read', name='a'))

    def test_R04_embed_rejected_even_when_get_string_hides_it(self):
        self.pair('safe')
        self.reject_unchanged(packet(info=5, content=buf('{"private":"HIDDEN"}')))

    def test_R05_format_rejected(self):
        self.pair('safe')
        self.reject_unchanged(packet(info=6, content=buf('bold') + buf('true')))

    def test_R06_nested_shared_type_rejected(self):
        self.pair('safe')
        self.reject_unchanged(packet(info=7, content=var(2)))

    def test_R07_map_slot_rejected(self):
        self.pair('safe')
        self.reject_unchanged(packet(info=0x24, content=buf('slot') + buf('HIDDEN')))

    def test_R08_missing_nested_parent_rejected_before_pending_storage(self):
        self.pair('safe')
        self.reject_unchanged(packet(parent=(99, 0)))
        self.assertFalse(self.b.ok('read', name='a')['pending'])

    def test_R09_conflicting_reserved_seed_rejected(self):
        self.pair('safe')
        self.reject_unchanged(self.seed('different'))

    def test_R10_deleted_seed_identity_survives_checkpoint(self):
        self.pair('safe')
        self.edit('a', 0, delete=4)
        checkpoint = self.b.ok('checkpoint', name='a')['checkpoint']
        self.b.ok('cancel', name='a')
        self.b.ok('restore', name='a', client=40, checkpoint=checkpoint)
        before = self.full('a')
        self.assertIn('error', self.b.request(op='apply', name='a', update=self.seed('different')))
        self.assertEqual(self.full('a'), before)
        self.assertEqual(self.text('a'), '')

    def test_R11_duplicate_full_state_with_split_seed_is_allowed(self):
        self.pair('A😀BC')
        self.edit('b', 3, 'REMOTE')
        self.edit('b', 0, delete=1)
        state = self.full('b')
        self.apply('a', state)
        self.apply('a', state)
        self.assertEqual(self.text('a'), '😀REMOTEBC')

    def test_R12_conflicting_nonseed_actor_overlap_rejected(self):
        self.pair('safe')
        # Different byte content at the same actor/clock must not be hidden by
        # the engine's usual idempotent duplicate handling.
        self.apply('a', packet(client=50, content=buf('FIRST')))
        before = self.full('a')
        self.assertIn('error', self.b.request(op='apply', name='a', update=packet(client=50, content=buf('WRONG'))))
        self.assertEqual(self.full('a'), before)

    def test_R13_trailing_bytes_rejected_without_mutation(self):
        self.pair('safe')
        raw = base64.b64decode(self.seed('safe')) + b'HIDDEN'
        self.reject_unchanged(base64.b64encode(raw).decode())

    def test_R14_reserved_seed_cannot_extend_its_original_identity(self):
        self.pair('safe')
        self.reject_unchanged(self.seed('safe extension'))
