import unittest
from dataclasses import replace
from datetime import datetime, timedelta

from household_update_policy import (CLOSE_THEN_UPDATE, DEFER, DONE, UPDATE, WAKE, Rollout,
                                     Signals, decide)

NOW = datetime(2026, 11, 2, 3)
OLD, TARGET = '2026.10.10', '2026.11.0'
IDLE = Signals(collected_at=NOW, awake=True, last_input_age=timedelta(hours=2),
               game_running=False, media_playing=False, tandemlog_open=False,
               pending_writes=False, installed=OLD)


def action(signals, first_seen=NOW, **kwargs):
    return decide(TARGET, signals, NOW, first_seen, **kwargs).action


class HouseholdUpdatePolicyTest(unittest.TestCase):
    def test_idle_host_updates_and_open_app_closes_first(self):
        self.assertEqual(action(IDLE), UPDATE)
        self.assertEqual(action(replace(IDLE, tandemlog_open=True)), CLOSE_THEN_UPDATE)

    def test_any_use_defers(self):
        for busy in (dict(last_input_age=timedelta(minutes=1)), dict(game_running=True),
                     dict(media_playing=True), dict(pending_writes=True),
                     dict(pending_writes=True, tandemlog_open=True)):
            with self.subTest(busy):
                self.assertEqual(action(replace(IDLE, **busy)), DEFER)

    def test_each_unknown_signal_defers(self):
        for name in ('awake', 'last_input_age', 'game_running', 'media_playing',
                     'tandemlog_open', 'pending_writes', 'installed', 'collected_at'):
            with self.subTest(name):
                self.assertEqual(action(replace(IDLE, **{name: None})), DEFER)

    def test_stale_signals_defer_at_the_boundary(self):
        self.assertEqual(action(replace(IDLE, collected_at=NOW - timedelta(minutes=5))), UPDATE)
        self.assertEqual(action(replace(IDLE, collected_at=NOW - timedelta(minutes=6))), DEFER)

    def test_asleep_defers_until_overdue_and_only_if_wakeable(self):
        asleep = Signals(awake=False)
        self.assertEqual(action(asleep, wakeable=True), DEFER)
        late = NOW - timedelta(days=8)
        self.assertEqual(action(asleep, first_seen=late), DEFER)
        self.assertEqual(action(asleep, first_seen=late, wakeable=True), WAKE)

    def test_awake_host_is_never_woken(self):
        late = NOW - timedelta(days=8)
        self.assertEqual(action(IDLE, first_seen=late, wakeable=True), UPDATE)

    def test_version_rules(self):
        self.assertEqual(action(replace(IDLE, installed=TARGET)), DONE)
        self.assertEqual(action(replace(IDLE, installed='2026.11.1')), DEFER)
        self.assertEqual(action(replace(IDLE, installed='2026.11.0-rc.2')), UPDATE)
        with self.assertRaises(ValueError):
            decide('2026.11.0-rc.1', IDLE, NOW, NOW)
        with self.assertRaises(ValueError):
            decide('latest', IDLE, NOW, NOW)

    def test_rollout_is_done_only_after_verified_version(self):
        rollout = Rollout(TARGET, NOW)
        hosts = ['a', 'b']
        rollout.record('a', OLD)
        self.assertEqual(rollout.pending(hosts), hosts)
        rollout.record('a', TARGET)
        self.assertEqual(rollout.pending(hosts), ['b'])
        rollout.record('b', TARGET)
        self.assertEqual(rollout.pending(hosts), [])


if __name__ == '__main__':
    unittest.main()
