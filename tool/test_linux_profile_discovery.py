"""Execute the production discovery branch, replacing only its final exec."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / 'packaging/linux/tandemlog'

class ProfileDiscovery(unittest.TestCase):
    def run_launcher(self, files=(), override=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in files:
                file = root / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('synthetic')
            env = dict(os.environ, TANDEMLOG_HOST_DATA_HOME=directory)
            env.pop('TANDEMLOG_PROFILE', None)
            if override is not None:
                env['TANDEMLOG_PROFILE'] = override
            source = LAUNCHER.read_text()
            self.assertEqual(source.count('exec /app/tandemlog/tandemlog "$@"'), 1)
            source = source.replace('exec /app/tandemlog/tandemlog "$@"', 'printf "%s\\n" "$TANDEMLOG_PROFILE"')
            result = subprocess.run(['/bin/sh', '-c', source], env=env, text=True, capture_output=True)
            return result.returncode, result.stdout.strip().removeprefix(directory), result.stderr

    def test_empty_modern_and_legacy_settings_select_legacy(self):
        self.assertEqual(self.run_launcher(['tandemlog/settings.json'])[:2], (0, '/tandemlog'))

    def test_migrated_legacy_database_stays_selected(self):
        self.assertEqual(self.run_launcher(['tandemlog/local.sqlite'])[:2], (0, '/tandemlog'))

    def test_modern_database_and_fresh_default(self):
        for files in [[], ['com.reddraggone9.tandemlog/local.sqlite']]:
            self.assertEqual(self.run_launcher(files)[:2], (0, '/com.reddraggone9.tandemlog'))

    def test_two_populated_roots_stop_without_silent_selection(self):
        result = self.run_launcher(['tandemlog/local.sqlite', 'com.reddraggone9.tandemlog/settings.json'])
        self.assertNotEqual(result[0], 0)
        self.assertEqual(result[1], '')
        self.assertIn('TANDEMLOG_PROFILE', result[2])

    def test_explicit_override_wins_even_with_competing_roots(self):
        self.assertEqual(self.run_launcher(['tandemlog/local.sqlite', 'com.reddraggone9.tandemlog/local.sqlite'], '/chosen/profile')[:2], (0, '/chosen/profile'))

if __name__ == '__main__':
    unittest.main()
