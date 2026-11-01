"""Decide, per host, whether a stable Tandemlog update may proceed now.

Pure policy: it runs no command and reaches no host, so callers supply signals
and carry out the single returned decision. Unknown or stale evidence defers.
Goal (Lee 10-30): stable reaches every household host without interrupting use.
"""
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from app_version import release_components

UPDATE = 'update'
CLOSE_THEN_UPDATE = 'close-then-update'
DEFER = 'defer'
DONE = 'done'
WAKE = 'wake'


@dataclass(frozen=True)
class Policy:
    idle_after: timedelta = timedelta(minutes=30)
    signals_fresh_for: timedelta = timedelta(minutes=5)
    # Asleep hosts catch up when next awake. Lee allows a wake only once overdue.
    overdue_after: timedelta = timedelta(days=7)


@dataclass(frozen=True)
class Signals:
    collected_at: datetime | None = None
    awake: bool | None = None
    last_input_age: timedelta | None = None
    game_running: bool | None = None
    media_playing: bool | None = None
    tandemlog_open: bool | None = None
    pending_writes: bool | None = None
    installed: str | None = None


@dataclass(frozen=True)
class Decision:
    action: str
    reason: str


def version_key(version):
    # release_components rejects anything not CalVer; RC sorts before its stable.
    major, minor, patch, rc = release_components(version)
    return (major, minor, patch, rc is None, rc or 0)


def decide(target, signals, now, first_seen, policy=Policy(), wakeable=False):
    """One decision for one host, recomputed immediately before every action."""
    target_key = version_key(target)
    if '-rc.' in target:
        raise ValueError('Prereleases never roll out to the household')
    if signals.awake is False:
        if wakeable and now - first_seen >= policy.overdue_after:
            return Decision(WAKE, 'overdue and asleep')
        return Decision(DEFER, 'asleep')
    if signals.collected_at is None or now - signals.collected_at > policy.signals_fresh_for:
        return Decision(DEFER, 'signals stale')
    required = {
        'awake': signals.awake,
        'recent input': signals.last_input_age,
        'game': signals.game_running,
        'media': signals.media_playing,
        'Tandemlog state': signals.tandemlog_open,
        'pending writes': signals.pending_writes,
        'installed version': signals.installed,
    }
    unknown = [name for name, value in required.items() if value is None]
    if unknown:
        return Decision(DEFER, f'unknown: {", ".join(unknown)}')
    installed_key = version_key(signals.installed)
    if installed_key == target_key:
        return Decision(DONE, 'already at target')
    if installed_key > target_key:
        return Decision(DEFER, 'host is newer than target; never downgrade')
    if signals.last_input_age < policy.idle_after:
        return Decision(DEFER, 'recent input')
    if signals.game_running:
        return Decision(DEFER, 'game running')
    if signals.media_playing:
        return Decision(DEFER, 'media playing')
    if signals.pending_writes:
        # Closing is authorized; discarding an unfinished write is not.
        return Decision(DEFER, 'Tandemlog has pending writes')
    if signals.tandemlog_open:
        return Decision(CLOSE_THEN_UPDATE, 'idle with Tandemlog open')
    return Decision(UPDATE, 'idle')


@dataclass
class Rollout:
    """Durable state for one target: done only after a verified installed version."""

    target: str
    started: datetime
    hosts: dict = field(default_factory=dict)

    def record(self, host, installed):
        if installed == self.target:
            self.hosts[host] = DONE
        else:
            self.hosts[host] = f'pending: installed {installed}'

    def pending(self, all_hosts):
        return [host for host in all_hosts if self.hosts.get(host) != DONE]
