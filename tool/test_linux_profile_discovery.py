"""Run the shipped launcher against synthetic sandbox and old host roots."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LAUNCHER = Path(__file__).resolve().parents[1] / 'packaging/linux/tandemlog'


@unittest.skipUnless(sys.platform.startswith('linux'), 'Linux launcher requires Linux /bin/sh')
class ProfileDiscovery(unittest.TestCase):
    def run_launcher(self, files=(), override=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in files:
                file = root / 'host' / relative
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('synthetic')
            before = {str(p.relative_to(root)): p.read_bytes()
                      for p in root.rglob('*') if p.is_file()}
            env = dict(os.environ, HOME=str(root / 'home'),
                       XDG_DATA_HOME=str(root / 'sandbox/data'),
                       TANDEMLOG_HOST_DATA_HOME=str(root / 'host'))
            env.pop('TANDEMLOG_PROFILE', None)
            if override is not None:
                env['TANDEMLOG_PROFILE'] = override
            source = LAUNCHER.read_text()
            self.assertEqual(source.count('exec /app/tandemlog/tandemlog "$@"'), 1)
            source = source.replace('exec /app/tandemlog/tandemlog "$@"',
                                    'printf "%s\\n%s\\n" "${TANDEMLOG_PROFILE-unset}" "$XDG_DATA_HOME"')
            result = subprocess.run(['/bin/sh', '-c', source], env=env,
                                    text=True, capture_output=True)
            self.assertEqual(before, {str(p.relative_to(root)): p.read_bytes()
                                     for p in root.rglob('*') if p.is_file()})
            return result.returncode, result.stdout.splitlines(), result.stderr, env

    def test_fresh_default_uses_sandbox_xdg_without_profile_override(self):
        code, lines, _, env = self.run_launcher()
        self.assertEqual(code, 0)
        self.assertEqual(lines, ['unset', env['XDG_DATA_HOME']])

    def test_host_profiles_are_not_discovered_copied_or_selected(self):
        for files in [['tandemlog/settings.json'],
                      ['com.reddraggone9.tandemlog/local.sqlite'],
                      ['tandemlog/local.sqlite', 'com.reddraggone9.tandemlog/settings.json']]:
            code, lines, _, env = self.run_launcher(files)
            self.assertEqual(code, 0)
            self.assertEqual(lines, ['unset', env['XDG_DATA_HOME']])

    def test_explicit_override_remains_authoritative(self):
        code, lines, _, env = self.run_launcher(
            ['tandemlog/local.sqlite', 'com.reddraggone9.tandemlog/local.sqlite'],
            '/chosen/profile')
        self.assertEqual(code, 0)
        self.assertEqual(lines, ['/chosen/profile', env['XDG_DATA_HOME']])


if __name__ == '__main__':
    unittest.main()
