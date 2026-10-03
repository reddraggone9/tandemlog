import unittest
import tempfile
import os
from unittest.mock import patch
from pathlib import Path
from android_release import check_candidate_codes, check_candidate_history, fingerprint, verify_apk, version
from candidate_source import validate_candidate_version, validate_run
from publish_gate import verify_install_smoke, verify_metadata
from release_assets import public_asset_names, stage_public_assets
from app_version import historical_version, release_components, verify_release_kind


class ReleaseGates(unittest.TestCase):
    def test_public_installers_are_versioned_and_byte_identical(self):
        for version in ('2026.10.0-rc.1', '2026.10.0'):
            names = public_asset_names(version)
            self.assertEqual(len(names), 3)
            self.assertTrue(all(name.startswith(f'tandemlog-{version}-') for name in names.values()))
        for invalid in ('../other', '0.1.0/extra', '0.1.0-rc.7+32', ''):
            with self.assertRaises(ValueError): public_asset_names(invalid)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'dist'
            source.mkdir()
            names = public_asset_names('2026.10.0-rc.1')
            for name in names: (source / name).write_bytes(name.encode())
            (source / 'android-signature.txt').write_text('Internal evidence')
            destination = root / 'public-assets'
            stage_public_assets('2026.10.0-rc.1', source, destination)
            self.assertEqual({p.name for p in destination.iterdir()}, set(names.values()))
            for original, public in names.items():
                self.assertEqual((source / original).read_bytes(), (destination / public).read_bytes())
            with self.assertRaises(FileExistsError):
                stage_public_assets('2026.10.0-rc.1', source, destination)

    def test_pin_requires_real_public_fingerprint(self):
        for value in ('', '# pending', 'a'*63, 'g'*64):
            with self.assertRaises(ValueError): fingerprint(value)
        self.assertEqual(fingerprint('# public\n'+'A'*64), 'a'*64)

    def test_apk_identity_and_install_metadata(self):
        cert = 'Signer #1 certificate SHA-256 digest: ' + 'a'*64
        badging = "package: name='com.reddraggone9.tandemlog' versionCode='5' versionName='0.1.0-rc.2'\nnative-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'"
        verify_apk(cert, badging, 'a'*64, ('0.1.0-rc.2', 5))
        for changed in (badging+'\napplication-debuggable', badging.replace("'5'", "'4'"),
                        badging.replace(" 'x86_64'", ''), badging.replace('com.reddraggone9.tandemlog', 'another.app')):
            with self.assertRaises(ValueError): verify_apk(cert, changed, 'a'*64, ('0.1.0-rc.2', 5))
        with self.assertRaises(ValueError): verify_apk(cert, badging, 'b'*64, ('0.1.0-rc.2', 5))
        with self.assertRaises(ValueError): verify_apk(cert+'\n'+cert, badging, 'a'*64, ('0.1.0-rc.2', 5))

    def test_untagged_candidate_version_floor(self):
        check_candidate_codes(6, [1, 4, 5])
        for code in (4, 5):
            with self.assertRaises(ValueError): check_candidate_codes(code, [5])

    def test_publication_floor_excludes_accepted_source_not_dispatch_commit(self):
        accepted, newer, dispatch = 'a'*40, 'b'*40, 'c'*40
        with patch.dict(os.environ, GITHUB_REPOSITORY='owner/repo', GITHUB_SHA=dispatch):
            with patch('android_release.subprocess.check_output', return_value=accepted+'\n') as command:
                check_candidate_history(('2026.10.0-rc.1', 38), accepted)
                self.assertEqual(command.call_count, 1)
            with patch('android_release.subprocess.check_output', side_effect=[
                    accepted+'\n'+newer+'\n', 'version: 2026.10.0-rc.2+39']):
                with self.assertRaises(ValueError):
                    check_candidate_history(('2026.10.0-rc.1', 38), accepted)

    def test_version_requires_explicit_build(self):
        self.assertEqual(version('version: 2026.10.0-rc.1+38'), ('2026.10.0-rc.1', 38))
        self.assertEqual(version('version: 2026.10.0+39'), ('2026.10.0', 39))
        for invalid in ('2026.10.0-rc.1', '2026.01.0+38', '2026.13.0+38',
                        '2026.0.0+38', '2026.10.00+38', '2026.10.0-rc.0+38',
                        '2026.10.0-beta.1+38', '2026.10.0+0', '2026.10.0+038',
                        '0.1.0-rc.2+5'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                version('version: ' + invalid)

    def test_historical_names_only_preserve_monotonic_build_floor(self):
        self.assertEqual(historical_version('version: 0.1.0-rc.10+37'), ('0.1.0-rc.10', 37))
        self.assertEqual(historical_version('version: 2026.10.0-rc.1+38'), ('2026.10.0-rc.1', 38))
        with self.assertRaises(ValueError): historical_version('version: arbitrary+39')
        with self.assertRaises(ValueError): check_candidate_codes(37, [historical_version('version: 0.1.0-rc.10+37')[1]])

    def test_windows_resource_does_not_silently_truncate(self):
        self.assertEqual(version('version: 2026.10.65535+65535')[1], 65535)
        for invalid in ('2026.10.65536+38', '2026.10.0+65536'):
            with self.assertRaises(ValueError): version('version: ' + invalid)

    def test_stable_and_preview_publication_are_separate_explicit_gates(self):
        verify_release_kind('2026.10.0-rc.1', 'prerelease')
        verify_release_kind('2026.10.0', 'stable', lee_accepted=True)
        for name, kind, accepted in [('2026.10.0', 'prerelease', True),
                                     ('2026.10.0-rc.1', 'stable', True),
                                     ('2026.10.0', 'stable', False),
                                     ('2026.10.0', 'unknown', True)]:
            with self.assertRaises(ValueError): verify_release_kind(name, kind, accepted)

    def test_candidate_provenance(self):
        run = dict(event='workflow_dispatch', head_branch='main', path='.github/workflows/android-candidate.yml',
                   status='completed', conclusion='success', head_sha='a'*40,
                   repository={'full_name':'owner/repo'}, head_repository={'full_name':'owner/repo'})
        self.assertEqual(validate_run(run, 'owner/repo'), 'a'*40)
        for key, value in [('event','pull_request'), ('head_branch','other'), ('conclusion','failure'),
                           ('path','.github/workflows/ci.yml'), ('head_sha','invalid'),
                           ('head_repository',{'full_name':'other/repo'})]:
            with self.assertRaises(ValueError): validate_run(dict(run, **{key:value}), 'owner/repo')

    def test_trusted_dispatch_rejects_older_rc_or_wrong_channel_candidate(self):
        preview = 'version: 2026.10.0-rc.1+38'
        stable = 'version: 2026.10.0+39'
        validate_candidate_version(preview, 'v2026.10.0-rc.1', 'prerelease')
        validate_candidate_version(stable, 'v2026.10.0', 'stable', True)
        for spec, tag, kind, accepted in [
                ('version: 0.1.0-rc.10+37', 'v0.1.0-rc.10', 'stable', True),
                (preview, 'v2026.10.0-rc.1', 'stable', True),
                (stable, 'v2026.10.0', 'prerelease', True),
                (stable, 'v2026.10.0', 'stable', False),
                (preview, 'v2026.10.0-rc.2', 'prerelease', False)]:
            with self.assertRaises(ValueError):
                validate_candidate_version(spec, tag, kind, accepted)

    def test_installed_desktop_lifecycle_gate(self):
        phases = [dict(phase=name, passed=True, loaded_projection=name != 'after-uninstall',
                       sandbox_stopped=name != 'after-uninstall')
                  for name in ('after-install', 'after-upgrade', 'after-uninstall', 'after-reinstall')]
        verify_install_smoke({'phases': phases})
        for report in ({}, {'phases': phases[:-1]}, {'phases': phases[::-1]},
                       {'phases': [dict(p, passed=False) for p in phases]},
                       {'phases': [dict(p, loaded_projection=False) for p in phases]}):
            with self.assertRaises(ValueError): verify_install_smoke(report)

    def test_flatpak_requires_real_commit_replacement(self):
        phases = [dict(phase=name, passed=True, loaded_projection=name != 'after-uninstall',
                       sandbox_stopped=name != 'after-uninstall')
                  for name in ('after-install', 'after-upgrade', 'after-uninstall', 'after-reinstall')]
        upgrade = dict(candidate_commit='a'*64, baseline_commit='b'*64,
                       baseline_payload_equal=True, baseline_permissions_equal=True,
                       final_candidate_restored=True)
        verify_install_smoke(dict(phases=phases, upgrade=upgrade), require_changed_commit=True)
        with self.assertRaises(ValueError):
            verify_install_smoke(dict(phases=[dict(p, sandbox_stopped=False) for p in phases],
                                      upgrade=upgrade), require_changed_commit=True)
        for changed in ({}, dict(upgrade, baseline_commit='a'*64),
                        dict(upgrade, baseline_payload_equal=False),
                        dict(upgrade, baseline_permissions_equal=False),
                        dict(upgrade, final_candidate_restored=False)):
            with self.assertRaises(ValueError):
                verify_install_smoke(dict(phases=phases, upgrade=changed), require_changed_commit=True)

    def test_exact_accepted_artifact(self):
        metadata = dict(source_commit='a'*40, apk_sha256='b'*64, certificate_sha256='c'*64, version='0.1.0-rc.2', version_code=5)
        verify_metadata(metadata, 'a'*40, 'b'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)
        for key, value in [('source_commit','d'*40), ('apk_sha256','d'*64), ('certificate_sha256','d'*64), ('version_code',4)]:
            with self.assertRaises(ValueError): verify_metadata(dict(metadata, **{key:value}), 'a'*40, 'b'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)
        with self.assertRaises(ValueError): verify_metadata(metadata, 'a'*40, 'd'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)


if __name__ == '__main__': unittest.main()
