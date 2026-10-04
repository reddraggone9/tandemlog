"""Review-driven cases written/red-recorded before ownership fixes.

The original 34-case hashes are unchanged. The captured draft intentionally
does not import remote operations; incoming work lives in the committed target.
"""
import unittest
import test_contract as contract


class Ownership(unittest.TestCase):
    setUp=contract.Contract.setUp
    pair=contract.Contract.pair
    seed=contract.Contract.seed
    draft=contract.Contract.draft
    edit=contract.Contract.edit
    full=contract.Contract.full
    text=contract.Contract.text
    apply=contract.Contract.apply
    def test_O01_draft_cannot_save_to_different_source(self):
        self.pair('x'); self.draft(); self.edit('draft',1,'L')
        before=self.full('b')
        self.assertIn('error',self.b.request(op='save',name='draft',target='b'))
        self.assertEqual(self.full('b'),before)
        self.assertEqual(self.text('draft'),'xL')

    def test_O02_incoming_update_cannot_be_attributed_to_draft(self):
        self.pair('x'); self.draft()
        remote=self.edit('b',0,'REMOTE')
        self.assertIn('error',self.b.request(op='apply',name='draft',update=remote))
        self.assertEqual(self.text('draft'),'x')
        self.apply('a',remote)
        self.edit('draft',1,'L'); self.b.ok('save',name='draft',target='a')
        self.b.ok('undo',name='a')
        self.assertEqual(self.text('a'),'REMOTEx')

    def test_O03_successful_save_consumes_draft_once(self):
        self.pair('x'); self.draft(); self.edit('draft',1,'L')
        self.b.ok('save',name='draft',target='a'); before=self.full('a')
        self.assertIn('error',self.b.request(op='save',name='draft',target='a'))
        self.assertEqual(self.full('a'),before)

    def test_O04_failed_save_preserves_prior_undo_and_draft(self):
        self.pair('x'); self.edit('a',1,'OLD'); self.draft(); self.edit('draft',4,'NEW')
        self.b.ok('composition',name='draft',active=True)
        self.assertIn('error',self.b.request(op='save',name='draft',target='a'))
        self.assertEqual(self.text('draft'),'xOLDNEW')
        self.b.ok('undo',name='a'); self.assertEqual(self.text('a'),'x')
