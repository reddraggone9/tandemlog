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

    def publish_rc(self, prerelease=True, latest=1):
        tag = 'v2030.1.1-rc.1'
        self.release.update(tag_name=tag, name=tag + ' — experimental', prerelease=prerelease)
        self.state['tag'] = tag
        self.save('draft-release.json', self.state)
        argv = ['publish-stable.py', '--repo-dir', str(self.root), '--output', str(self.root), '--tag', tag, 'publish']
        with patch.object(sys, 'argv', argv):
            g = runpy.run_path(str(TOOL / 'publish-stable.py'), run_name='test_module')
        final = dict(self.release, draft=False, published_at='now', html_url='url')
        api = unittest.mock.Mock(side_effect=[self.release, {'id': 1}, final, {'id': latest}])
        g['publish'].__globals__.update(api=api, run=lambda *a: self.sha, all_releases=lambda: [self.release])
        with contextlib.redirect_stdout(io.StringIO()):
            g['publish']()
        return api

    def draft(self, tag, *flags, remote_main=None):
        """Run draft() with every external command faked; returns the recorded commands."""
        (self.root/'draft-release.json').unlink(missing_ok=True)
        dist = self.root/'dist'; dist.mkdir(exist_ok=True)
        argv = ['publish-stable.py', '--repo-dir', str(self.root), '--output', str(self.root), '--tag', tag, *flags,
                'draft', '--dist', str(dist), '--run-id', '7', '--android-sha256', 'd' * 64]
        with patch.object(sys, 'argv', argv):
            g = runpy.run_path(str(TOOL / 'publish-stable.py'), run_name='test_module')
        calls, main = [], 'e' * 40
        notes = '![shot](media/x/1.png)\n'
        pinned = notes.replace('(media/', f'(https://raw.githubusercontent.com/reddraggone9/tandemlog/{main}/design/media/')
        def run(*a, cwd=None, extra=None):
            a = [str(x) for x in a]; calls.append((a, extra or {}))
            if 'worktree' in a:
                Path(a[-2]).mkdir()
            elif a[-1] == 'tool/candidate_source.py':
                Path(extra['GITHUB_OUTPUT']).write_text(f'sha={self.sha}\n')
            elif a[-1] == '.release-policy/release_assets.py':
                (Path(cwd)/'public-assets').mkdir()
                for n in range(4):
                    (Path(cwd)/'public-assets'/f'asset{n}').write_bytes(b'x')
            elif 'ls-remote' in a:
                return f'{remote_main or main}\trefs/heads/main\n'
            elif 'show' in a and a[-1].endswith('-notes.md'):
                return notes
            return main if 'rev-parse' in a else 'url'
        digest = 'sha256:' + hashlib.sha256(b'x').hexdigest()
        rel = dict(id=3, tag_name=tag, draft=True, prerelease='-rc.' in tag, target_commitish=self.sha, body=pinned,
                   name=tag + (' — experimental' if '-rc.' in tag else ''),
                   assets=[dict(name=f'asset{n}', digest=digest, size=1) for n in range(4)])
        releases = unittest.mock.Mock(side_effect=[[], [rel]])
        g['draft'].__globals__.update(run=run, all_releases=releases)
        with contextlib.redirect_stdout(io.StringIO()):
            g['draft'](dist, '7', 'd' * 64)
        return calls

    def test_rc_draft_runs_prerelease_gates_with_main_notes_and_pinned_media(self):
        calls = self.draft('v2030.1.1-rc.1')
        gates = [extra for a, extra in calls if a[0] == 'python3' and 'release_assets' not in a[-1]]
        self.assertEqual([e['RELEASE_KIND'] for e in gates], ['prerelease'] * 2)
        self.assertFalse(any('LEE_ACCEPTED_STABLE' in e for e in gates))
        create = next(a for a, _ in calls if a[:3] == ['gh', 'release', 'create'])
        self.assertIn('--prerelease', create)
        self.assertIn('v2030.1.1-rc.1 — experimental', create)
        self.assertIn(['git', '-C', str(self.root), 'show', 'e' * 40 + ':design/prerelease-notes.md'], [a for a, _ in calls])
        self.assertIn(['git', '-C', str(self.root), 'cat-file', '-e', 'e' * 40 + ':design/media/x/1.png'], [a for a, _ in calls])
        self.assertEqual(json.loads((self.root/'draft-release.json').read_text())['phase'], 'draft-verified')

    def test_stable_draft_keeps_stable_gates_and_stale_main_refuses(self):
        calls = self.draft('v2030.1.1', '--lee-accepted')
        gates = [extra for a, extra in calls if a[0] == 'python3' and 'release_assets' not in a[-1]]
        self.assertEqual([(e['RELEASE_KIND'], e['LEE_ACCEPTED_STABLE']) for e in gates], [('stable', 'true')] * 2)
        create = next(a for a, _ in calls if a[:3] == ['gh', 'release', 'create'])
        self.assertNotIn('--prerelease', create)
        self.assertIn(['git', '-C', str(self.root), 'show', 'e' * 40 + ':design/stable-notes.md'], [a for a, _ in calls])
        with self.assertRaises(AssertionError):
            self.draft('v2030.1.1', '--lee-accepted', remote_main='f' * 40)
        self.assertFalse((self.root/'draft-release.json').exists())

    def test_rc_publishes_as_prerelease_and_never_latest(self):
        patch_args = self.publish_rc().call_args_list[2].args
        self.assertIn('prerelease=true', patch_args)
        self.assertIn('make_latest=false', patch_args)
        self.assertNotIn('make_latest=true', patch_args)

    def test_rc_tag_refuses_stable_draft_and_moved_latest(self):
        with self.assertRaises(AssertionError):
            self.publish_rc(prerelease=False)
        with self.assertRaises(AssertionError):
            self.publish_rc(latest=2)

    def test_stable_tag_refuses_prerelease_draft_and_missing_acceptance(self):
        self.release['prerelease'] = True
        with self.assertRaises(AssertionError):
            self.publish()
        argv = ['publish-stable.py', '--repo-dir', str(self.root), '--output', str(self.root), '--tag', 'v2030.1.1', 'publish']
        with patch.object(sys, 'argv', argv), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            runpy.run_path(str(TOOL / 'publish-stable.py'), run_name='test_module')

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

    def verify_public(self, mutation=None, version='2030.1.1', latest=None):
        body = b'accepted apk'
        tag = 'v' + version
        name = f'tandemlog-{version}-android.apk'
        self.state['tag'] = tag
        release = dict(self.release, tag_name=tag, prerelease='-rc.' in tag, draft=False, immutable=True, html_url='url', published_at='now',
                       assets=[dict(self.asset, name=name, size=len(body), digest='sha256:'+hashlib.sha256(body).hexdigest(),
                                    browser_download_url='https://download.invalid/apk')])
        self.state['assets'] = asset_inventory(release)
        self.save('draft-release.json', self.state)
        self.save('prior-latest.json', {'id': 9, 'tag_name':'v2029.1.1'})
        self.save('prior-releases.json', [])
        self.save('prior-tags.json', [])
        (self.root/'release-notes-published.md').write_text('notes\n')
        if mutation:
            mutation(release)
        responses = {'/releases/tags/'+tag: release, '/releases/latest': latest or release,
                     '/git/ref/tags/'+tag: {'object':{'type':'commit', 'sha':self.sha}},
                     '/git/matching-refs/tags/': [{'ref':'refs/tags/'+tag,'object':{'sha':self.sha}}]}
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
        android.version.return_value = (version, 999)
        android.fingerprint.return_value = 'signer-pin'
        argv = ['verify-public.py','--repo-dir',str(self.root),'--output',str(self.root),
                '--tag',tag,'--build-tools',str(self.root)]
        with patch.object(sys,'argv',argv), patch('urllib.request.build_opener', return_value=opener), \
                patch('subprocess.check_output', return_value='source bytes'), \
                patch.dict(sys.modules, {'android_release':android}), contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(TOOL/'verify-public.py'))
        android.verify_apk.assert_called_once_with('source bytes','source bytes','signer-pin',(version,999))

    def test_public_downloads_anonymously_and_verifies_signer(self):
        self.verify_public()
        self.assertTrue(json.loads((self.root/'public-verification.json').read_text())['apkSignerVersionVerified'])

    def test_public_rc_is_prerelease_and_leaves_frozen_latest(self):
        frozen = {'id': 9, 'tag_name': 'v2029.1.1'}
        self.verify_public(version='2030.1.1-rc.1', latest=frozen)
        result = json.loads((self.root/'public-verification.json').read_text())
        self.assertEqual((result['prerelease'], result['latest']), (True, False))
        with self.assertRaises(AssertionError):  # An RC that became Latest.
            self.verify_public(version='2030.1.1-rc.1')
        with self.assertRaises(AssertionError):  # A stable that did not.
            self.verify_public(latest=frozen)

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
    def test_prepare_package_path_survives_sanitized_environment(self):
        # Execute the production heredoc with the same empty environment used
        # across sudo. Before the fix this raised KeyError(PACKAGE_CONFIG).
        script = (TOOL/'qualification/prepare.sh').read_text()
        block = script.split('import hashlib,json,pathlib,sys,urllib.parse\n', 1)[1].split('\nPY', 1)[0]
        import os
        sys.path.insert(0, str(TOOL/'performance'))
        from reference_receipt import package_contract
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); repo = root/'repo'; (repo/'tool').mkdir(parents=True)
            lock = b'locked'; (repo/'pubspec.lock').write_bytes(lock)
            config = dict(configVersion=2, packages=[dict(name='tandemlog', rootUri='../', languageVersion='3.13', packageUri='lib/')])
            profile = dict(packageNames=['tandemlog'], pubspecLockSHA256=hashlib.sha256(lock).hexdigest(), packageContractSHA256=package_contract(config))
            # Keep source module files real; only the registration is fixture data.
            import shutil
            shutil.copytree(TOOL/'performance', repo/'tool/performance')
            (repo/'tool/performance/reference-host-v1.json').write_text(json.dumps(profile))
            source = root/'package_config.json'; source.write_text(json.dumps(config))
            code = 'import hashlib,json,pathlib,sys,urllib.parse\n'+block
            result = subprocess.run([sys.executable, '-I', '-B', '-', str(repo), str(source)], input=code,
                                    env={'PATH': os.defpath}, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            generated = json.loads((repo/'.dart_tool/package_config.json').read_text())
            self.assertEqual(generated['packages'][0]['rootUri'], repo.as_uri()+'/')

    def test_prepare_accepts_schema2_observations_not_changed_hardware(self):
        script = (TOOL/'qualification/prepare.sh').read_text()
        block = script.split('import json,pathlib,sys\n', 1)[1].split('\nPY', 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            host = json.loads((TOOL/'performance/reference-host-v1.json').read_text())
            observed = dict(host['environment'], kernel='new-kernel', python='new-python')
            actual = Path(tmp)/'fingerprint.json'; actual.write_text(json.dumps(observed))
            code = 'import json,pathlib,sys\n'+block
            result = subprocess.run([sys.executable, '-B', '-', str(actual), str(TOOL.parent)], input=code, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            observed['cpuModel'] = 'wrong CPU'; actual.write_text(json.dumps(observed))
            result = subprocess.run([sys.executable, '-B', '-', str(actual), str(TOOL.parent)], input=code, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

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
