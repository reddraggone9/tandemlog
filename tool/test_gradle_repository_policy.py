import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class GradleRepositoryPolicyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='gradle-policy-test-')
        self.root = Path(self.temp.name)
        tools = Path(__file__).parent
        self.script = self.root / 'gradle_repository_policy.py'
        shutil.copyfile(tools / 'gradle_repository_policy.py', self.script)
        shutil.copyfile(tools / 'gradle-repositories.init.gradle', self.root / 'gradle-repositories.init.gradle')
        self.home = self.root / 'gradle-home'
        self.target = self.home / 'init.d' / 'tandemlog-repositories.gradle'
        self.env = dict(os.environ, GRADLE_USER_HOME=str(self.home))

    def tearDown(self):
        self.temp.cleanup()

    def run_policy(self, action):
        return subprocess.run([sys.executable, str(self.script), action], env=self.env, capture_output=True, text=True)

    def test_missing_and_mismatched_policy_block_verification(self):
        self.assertNotEqual(self.run_policy('verify').returncode, 0)
        self.assertEqual(self.run_policy('install').returncode, 0)
        self.assertEqual(self.run_policy('verify').returncode, 0)
        self.target.write_bytes(b'different policy')
        self.assertNotEqual(self.run_policy('verify').returncode, 0)
        self.assertNotEqual(self.run_policy('install').returncode, 0)
        self.assertEqual(self.target.read_bytes(), b'different policy')

    @unittest.skipIf(os.name == 'nt', 'Symlink creation requires a Windows privilege')
    def test_symlink_policy_destination_is_rejected_without_target_write(self):
        self.target.parent.mkdir(parents=True)
        other = self.root / 'untouched'
        other.write_bytes(b'preserve')
        self.target.symlink_to(other)
        self.assertNotEqual(self.run_policy('install').returncode, 0)
        self.assertNotEqual(self.run_policy('verify').returncode, 0)
        self.assertEqual(other.read_bytes(), b'preserve')

    def test_owner_signing_requires_policy_before_keystore_materialization(self):
        tools = Path(__file__).parent
        script = (tools / 'build_android_release.sh').read_text()
        self.assertLess(script.index('gradle_repository_policy.py verify'), script.index('base64 --decode'))
        self.assertLess(script.index('gradle_repository_policy.py verify'), script.index('flutter build apk --release'))

    def test_missing_or_overridden_gradle_home_cannot_report_unused_policy_valid(self):
        self.assertEqual(self.run_policy('install').returncode, 0)
        self.env.pop('GRADLE_USER_HOME')
        self.assertNotEqual(self.run_policy('verify').returncode, 0)
        self.env['GRADLE_USER_HOME'] = str(self.home)
        for name in ['GRADLE_OPTS', 'JAVA_OPTS', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS']:
            self.env[name] = '-Dgradle.user.home=/synthetic-other-home'
            self.assertNotEqual(self.run_policy('verify').returncode, 0)
            self.env.pop(name)
        self.assertEqual(self.run_policy('verify').returncode, 0)


if __name__ == '__main__':
    unittest.main()
