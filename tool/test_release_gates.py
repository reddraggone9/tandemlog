import unittest
from android_release import check_candidate_codes, fingerprint, verify_apk, version
from candidate_source import validate_run
from publish_gate import verify_metadata


class ReleaseGates(unittest.TestCase):
    def test_pin_requires_real_public_fingerprint(self):
        for value in ('', '# pending', 'a'*63, 'g'*64):
            with self.assertRaises(ValueError): fingerprint(value)
        self.assertEqual(fingerprint('# public\n'+'A'*64), 'a'*64)

    def test_apk_identity_and_install_metadata(self):
        cert = 'Signer #1 certificate SHA-256 digest: ' + 'a'*64
        badging = "package: name='dev.tandemlog.tandemlog' versionCode='5' versionName='0.1.0-rc.2'\nnative-code: 'armeabi-v7a' 'arm64-v8a' 'x86_64'"
        verify_apk(cert, badging, 'a'*64, ('0.1.0-rc.2', 5))
        for changed in (badging+'\napplication-debuggable', badging.replace("'5'", "'4'"),
                        badging.replace(" 'x86_64'", ''), badging.replace('dev.tandemlog.tandemlog', 'another.app')):
            with self.assertRaises(ValueError): verify_apk(cert, changed, 'a'*64, ('0.1.0-rc.2', 5))
        with self.assertRaises(ValueError): verify_apk(cert, badging, 'b'*64, ('0.1.0-rc.2', 5))
        with self.assertRaises(ValueError): verify_apk(cert+'\n'+cert, badging, 'a'*64, ('0.1.0-rc.2', 5))

    def test_untagged_candidate_version_floor(self):
        check_candidate_codes(6, [1, 4, 5])
        for code in (4, 5):
            with self.assertRaises(ValueError): check_candidate_codes(code, [5])

    def test_version_requires_explicit_build(self):
        self.assertEqual(version('version: 0.1.0-rc.2+5'), ('0.1.0-rc.2', 5))
        with self.assertRaises(ValueError): version('version: 0.1.0-rc.2')

    def test_candidate_provenance(self):
        run = dict(event='workflow_dispatch', head_branch='main', path='.github/workflows/android-candidate.yml',
                   status='completed', conclusion='success', head_sha='a'*40,
                   repository={'full_name':'owner/repo'}, head_repository={'full_name':'owner/repo'})
        self.assertEqual(validate_run(run, 'owner/repo'), 'a'*40)
        for key, value in [('event','pull_request'), ('head_branch','other'), ('conclusion','failure'),
                           ('path','.github/workflows/ci.yml'), ('head_sha','invalid'),
                           ('head_repository',{'full_name':'other/repo'})]:
            with self.assertRaises(ValueError): validate_run(dict(run, **{key:value}), 'owner/repo')

    def test_exact_accepted_artifact(self):
        metadata = dict(source_commit='a'*40, apk_sha256='b'*64, certificate_sha256='c'*64, version='0.1.0-rc.2', version_code=5)
        verify_metadata(metadata, 'a'*40, 'b'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)
        for key, value in [('source_commit','d'*40), ('apk_sha256','d'*64), ('certificate_sha256','d'*64), ('version_code',4)]:
            with self.assertRaises(ValueError): verify_metadata(dict(metadata, **{key:value}), 'a'*40, 'b'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)
        with self.assertRaises(ValueError): verify_metadata(metadata, 'a'*40, 'd'*64, 'b'*64, ('0.1.0-rc.2',5), 'c'*64)


if __name__ == '__main__': unittest.main()
