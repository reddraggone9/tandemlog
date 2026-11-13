"""Release-state regression tests; never access GitHub or launch qualification."""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from release_context import asset_inventory

TOOL = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOL / 'qualification'))
from unit_cleanup import reset_owned
import quiet_admission


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sha = 'a' * 40
        self.asset = {'id': 1, 'name': 'installer.apk', 'digest': 'sha256:' + 'b' * 64, 'size': 3}
        self.release = dict(id=2, tag_name='v2030.1.1', prerelease=False, draft=True,
                            body='notes\n', target_commitish=self.sha, name='v2030.1.1',
                            assets=[self.asset])
        self.state = dict(phase='draft-verified', tag='v2030.1.1', source=self.sha,
                          releaseId=2, assets=asset_inventory(self.release),
                          notesSHA256=hashlib.sha256(b'notes\n').hexdigest())
        self.save('draft-release.json', self.state)
        self.save('releases-before-publish.json', [])

    def save(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def publisher(self):
        argv = ['publish-stable.py', '--repo-dir', str(self.root), '--output', str(self.root),
                '--tag', 'v2030.1.1', '--lee-accepted', 'publish']
        with patch.object(sys, 'argv', argv):
            return runpy.run_path(str(TOOL / 'publish-stable.py'), run_name='test_module')

    def publish(self, releases=None):
        g = self.publisher()
        final = dict(self.release, draft=False, published_at='now', html_url='url')
        api = unittest.mock.Mock(side_effect=[self.release, final])
        g['publish'].__globals__.update(api=api, run=lambda *a: self.sha,
                                       all_releases=lambda: releases or [self.release])
        with contextlib.redirect_stdout(io.StringIO()):
            g['publish']()
        return api

    def test_publish_exact_draft(self):
        api = self.publish()
        self.assertEqual(api.call_count, 2)
        self.assertEqual(json.loads((self.root/'draft-release.json').read_text())['phase'], 'published')

    def test_changed_asset_refuses_publish(self):
        self.release['assets'][0]['size'] = 4
        with self.assertRaises(AssertionError):
            self.publish()

    def test_changed_notes_refuses_publish(self):
        self.release['body'] = 'wrong'
        with self.assertRaises(AssertionError):
            self.publish()

    def test_changed_source_refuses_publish(self):
        self.release['target_commitish'] = 'c' * 40
        with self.assertRaises(AssertionError):
            self.publish()

    def test_prior_release_added_refuses_publish(self):
        prior = dict(self.release, id=4, tag_name='v2029.1.1')
        with self.assertRaises(AssertionError):
            self.publish([self.release, prior])

    def test_wrong_phase_refuses_publish(self):
        self.state['phase'] = 'publishing'
        self.save('draft-release.json', self.state)
        with self.assertRaises(AssertionError):
            self.publish()

    def test_assets_require_digest_and_safe_unique_names(self):
        for mutate in (lambda a: a.update(name='../evil'), lambda a: a.update(digest=None),
                       lambda a: a.update(name='..')):
            release = copy.deepcopy(self.release)
            mutate(release['assets'][0])
            with self.assertRaises(ValueError):
                asset_inventory(release)
        release = copy.deepcopy(self.release)
        release['assets'] *= 2
        with self.assertRaises(ValueError):
            asset_inventory(release)

    def test_freeze_arbitrary_tag_and_no_overwrite(self):
        target = 'v2031.2.3'
        argv = ['freeze-prior.py', '--repo-dir', str(self.root), '--output', str(self.root), '--tag', target]
        class Response(io.BytesIO):
            def __enter__(self): return self
            def __exit__(self, *a): self.close()
        def fetch(req, timeout):
            data = {'tag_name': 'v2030.1.1'} if req.full_url.endswith('/latest') else []
            return Response(json.dumps(data).encode())
        opener = unittest.mock.Mock()
        opener.open.side_effect = fetch
        with patch.object(sys, 'argv', argv), patch('urllib.request.build_opener', return_value=opener):
            with contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(TOOL / 'freeze-prior.py'))
            count = opener.open.call_count
            with self.assertRaises(AssertionError):
                runpy.run_path(str(TOOL / 'freeze-prior.py'))
            self.assertEqual(opener.open.call_count, count)

    def test_existing_target_tag_refuses_freeze(self):
        argv = ['freeze-prior.py', '--repo-dir', str(self.root), '--output', str(self.root), '--tag', 'v2031.2.3']
        opener = unittest.mock.Mock()
        def fetch(req, timeout):
            data = ([{'ref': 'refs/tags/v2031.2.3'}] if '/git/refs/' in req.full_url
                    else {'tag_name': 'v2030.1.1'} if req.full_url.endswith('/latest') else [])
            return contextlib.closing(io.BytesIO(json.dumps(data).encode()))
        opener.open.side_effect = fetch
        with patch.object(sys, 'argv', argv), patch('urllib.request.build_opener', return_value=opener):
            with self.assertRaises(AssertionError):
                runpy.run_path(str(TOOL / 'freeze-prior.py'))
        self.assertFalse((self.root/'prior-tags.json').exists())

    def verify_public(self, mutation=None):
        body = b'accepted apk'
        name = 'tandemlog-2030.1.1-android.apk'
        release = dict(self.release, draft=False, immutable=True, html_url='url', published_at='now',
                       assets=[dict(self.asset, name=name, size=len(body), digest='sha256:'+hashlib.sha256(body).hexdigest(),
                                    browser_download_url='https://download.invalid/apk')])
        self.state['assets'] = asset_inventory(release)
        self.save('draft-release.json', self.state)
        self.save('prior-latest.json', {'tag_name':'v2029.1.1'})
        self.save('prior-releases.json', [])
        self.save('prior-tags.json', [])
        (self.root/'release-notes-published.md').write_text('notes\n')
        if mutation:
            mutation(release)
        responses = {'/releases/tags/v2030.1.1': release, '/releases/latest': release,
                     '/git/ref/tags/v2030.1.1': {'object':{'type':'commit', 'sha':self.sha}},
                     '/git/matching-refs/tags/': [{'ref':'refs/tags/v2030.1.1','object':{'sha':self.sha}}]}
        def fetch(req, timeout):
            self.assertNotIn('Authorization', req.headers)
            if req.full_url == 'https://download.invalid/apk':
                data = body
            else:
                key = req.full_url.split('/repos/reddraggone9/tandemlog')[1]
                data = json.dumps(responses.get(key, [release] if key.endswith('&page=1') else [])).encode()
            return contextlib.closing(io.BytesIO(data))
        opener = unittest.mock.Mock()
        opener.open.side_effect = fetch
        android = unittest.mock.Mock()
        android.version.return_value = ('2030.1.1', 999)
        android.fingerprint.return_value = 'signer-pin'
        argv = ['verify-public.py','--repo-dir',str(self.root),'--output',str(self.root),
                '--tag','v2030.1.1','--build-tools',str(self.root)]
        with patch.object(sys,'argv',argv), patch('urllib.request.build_opener', return_value=opener), \
                patch('subprocess.check_output', return_value='source bytes'), \
                patch.dict(sys.modules, {'android_release':android}), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(TOOL/'verify-public.py'))
        android.verify_apk.assert_called_once_with('source bytes','source bytes','signer-pin',('2030.1.1',999))

    def test_public_downloads_anonymously_and_verifies_signer(self):
        self.verify_public()
        self.assertTrue(json.loads((self.root/'public-verification.json').read_text())['apkSignerVersionVerified'])

    def test_public_rejects_mutated_download(self):
        with self.assertRaises(AssertionError):
            self.verify_public(lambda r: r['assets'][0].update(digest='sha256:'+'f'*64))

    def test_public_requires_immutable(self):
        with self.assertRaises(AssertionError):
            self.verify_public(lambda r: r.update(immutable=False))

    def test_cli_help_no_external_actions(self):
        for script in ['publish-stable.py', 'verify-candidate.py', 'verify-public.py', 'freeze-prior.py',
                       'qualification/qualification.py', 'qualification/launch_reference.py']:
            result = subprocess.run([sys.executable, str(TOOL/script), '--help'], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


class QualificationTests(unittest.TestCase):
    def test_failed_units_read_before_reset(self):
        unit = 'tandemlog-reference-manager-' + 'a'*32 + '.service'
        with tempfile.TemporaryDirectory() as tmp:
            evidence = Path(tmp)/'result.json'
            def run(argv, **kw):
                if 'reset-failed' in argv:
                    self.assertTrue(evidence.exists())
                    self.assertEqual(json.loads(evidence.read_text())[unit]['Result'], 'exit-code')
                return subprocess.CompletedProcess(argv, 0, 'ActiveState=failed\nMainPID=0\nResult=exit-code\nExecMainStatus=1\n')
            reset_owned([unit], evidence, run=run)

    def test_active_or_unrelated_unit_never_reset(self):
        for unit, state in [('other.service', 'failed'), ('tandemlog-reference-workload-a.service', 'active')]:
            with tempfile.TemporaryDirectory() as tmp:
                mock = unittest.mock.Mock(return_value=subprocess.CompletedProcess([], 0, f'ActiveState={state}\nMainPID=0\n'))
                with self.assertRaises(ValueError):
                    reset_owned([unit], Path(tmp)/'result.json', run=mock)
                self.assertFalse(any('reset-failed' in c.args[0] for c in mock.call_args_list))

    def test_quiet_refuses_pressure_load_and_processes(self):
        state = dict(activeUnits=[], processes=[], load=[0.1], psi={'cpu': 'some avg10=0.00 avg60=0.00 avg300=0.00 total=0'})
        self.assertEqual(quiet_admission.refusals(state), [])
        for key, value in [('processes', ['flutter']), ('activeUnits', ['busy']), ('load', [2]), ('psi', None)]:
            self.assertTrue(quiet_admission.refusals(dict(state, **{key: value})))


if __name__ == '__main__':
    unittest.main()
