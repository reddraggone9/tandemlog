"""Additional postimplementation validation; original preimplementation freezes unchanged."""
import unittest
import test_resource_limits as budgets


class AtomicBudgetReceipt(unittest.TestCase):
    setUp = budgets.NativeBudgets.setUp
    limits = budgets.NativeBudgets.limits
    new = budgets.NativeBudgets.new
    seed = budgets.NativeBudgets.seed
    edit = budgets.NativeBudgets.edit
    full = budgets.NativeBudgets.full
    text = budgets.NativeBudgets.text
    usage = budgets.NativeBudgets.usage

    def test_A01_receipt_history_budget_rejection_keeps_preparation_and_live_undo(self):
        # Measured prepare weight244 / committed weight296; cap270 admits
        # preparation while forcing exact-receipt retention rejection.
        self.new(retainedBytes=270); self.edit('a', 1, 'L')
        prepared = self.b.ok('prepare_undo', name='a'); before = self.full('a')
        result = self.b.request(op='commit_undo', name='a', token=prepared['token'], receipt={'update': prepared['update']})
        self.assertIn('budget', result.get('error', '')); self.assertEqual(self.full('a'), before)
        self.assertEqual(self.b.ok('prepare_undo', name='a'), prepared)
        self.b.ok('cancel_prepared_undo', name='a', token=prepared['token'])
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')

    def test_A02_queued_remote_budget_rejection_preserves_live_and_frozen_packet(self):
        self.new(sessionBytes=120); self.edit('a', 1, 'L')
        self.b.ok('new', name='b', client=20, seed=self.seed('x'))
        prepared = self.b.ok('prepare_undo', name='a'); before = self.full('a')
        remote = self.edit('b', 0, 'REMOTE')
        result = self.b.request(op='apply', name='a', update=remote)
        self.assertIn('budget', result.get('error', '')); self.assertEqual(self.full('a'), before)
        self.assertEqual(self.b.ok('prepare_undo', name='a'), prepared)
        self.b.ok('cancel_prepared_undo', name='a', token=prepared['token'])
        self.b.ok('undo', name='a'); self.assertEqual(self.text('a'), 'x')


if __name__ == '__main__': unittest.main(verbosity=2)
