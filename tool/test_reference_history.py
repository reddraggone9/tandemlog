"""Sealed bundles keep their meaning: each verifies with the tooling of its own commit."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
# Commit -> (state or request id it must report). A shallow clone skips what it lacks.
SEALED = {
    'ca76e2dea81d52e192a9ad498259d14cdff3a989': ('state', 'OWNER_OVERRIDE_ACCEPTED_NOT_QUALIFIED'),
    'e3467118971a90df4b622884ee2f2be63feec8fe': ('state', 'OWNER_OVERRIDE_ACCEPTED_NOT_QUALIFIED'),
    '12b9f03b55915813345e8940c361ae58366ac02c': ('requestId', '50a8ca56db6f36a140e1af8ee5ef1dd7'),
    '436a68932c614b244e2d0bf61f6d419d6fe06f38': ('requestId', '8993c1aaa0b86d74a92b80eb91f5b8df'),
}


def git(*args, **kwargs):
    return subprocess.run(['git', '-C', str(REPO), *args], capture_output=True, text=True, **kwargs)


@unittest.skipUnless(sys.platform.startswith('linux'), 'Sealed Linux evidence; worktrees are slow on Windows')
class SealedBundleTests(unittest.TestCase):
    def test_each_bundle_verifies_at_its_own_commit(self):
        available = [c for c in SEALED if git('cat-file', '-e', c + '^{commit}').returncode == 0]
        if not available or git('rev-parse', '--is-shallow-repository').stdout.strip() == 'true':
            self.skipTest('Sealed commits are not in this clone')
        for commit in available:
            with self.subTest(commit=commit), tempfile.TemporaryDirectory() as temporary:
                checkout = Path(temporary) / 'checkout'
                self.assertEqual(git('worktree', 'add', '-q', '--detach', str(checkout), commit).returncode, 0)
                try:
                    result = subprocess.run([sys.executable, '-B', str(checkout / 'tool/performance/reference_receipt.py'),
                                             'verify', '--repo', str(checkout)], capture_output=True, text=True,
                                            env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}, timeout=120)
                finally:
                    git('worktree', 'remove', '--force', str(checkout))
                self.assertEqual(result.returncode, 0, result.stderr[-800:])
                key, value = SEALED[commit]
                self.assertEqual(json.loads(result.stdout)[key], value)


if __name__ == '__main__':
    unittest.main()
