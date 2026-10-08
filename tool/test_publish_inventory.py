import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from publish_gate import verify_candidate_inventory
from release_assets import public_asset_names, stage_public_assets


BASE_FILES = {
    'tandemlog-linux-x64.flatpak', 'linux-SHA256SUMS.txt', 'linux-startup.json',
    'linux-install-smoke.json', 'tandemlog-windows-x64-unsigned-setup.exe',
    'windows-SHA256SUMS.txt', 'windows-install-smoke.json', 'tandemlog-android.apk',
    'android-SHA256SUMS.txt', 'android-signature.txt', 'android-release-metadata.json',
}
QA_FILES = {
    'tandemlog-windows-x64-unsigned-portable.zip',
    'windows-portable-SHA256SUMS.txt', 'windows-portable-provenance.json',
}
SOURCE = 'a' * 40


class PublishInventory(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.dist = self.root / 'dist'
        self.dist.mkdir()
        for name in BASE_FILES:
            (self.dist / name).write_bytes(name.encode())

    def portable(self, payload=None):
        payload = payload or {
            'tandemlog.exe': b'app', 'tandemlog_text.dll': b'native',
            'flutter_windows.dll': b'flutter',
            'data/flutter_assets/AssetManifest.bin': b'assets',
        }
        archive = self.dist / 'tandemlog-windows-x64-unsigned-portable.zip'
        with zipfile.ZipFile(archive, 'w') as zipped:
            for name, data in payload.items():
                zipped.writestr(name, data)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (self.dist / 'windows-portable-SHA256SUMS.txt').write_text(
            f'{digest}  {archive.name}\n')
        self.metadata = dict(source_revision=SOURCE, github_run_id='123',
                             artifact=archive.name, artifact_sha256=digest,
                             payload_sha256={name: hashlib.sha256(data).hexdigest()
                                             for name, data in payload.items()})
        self.save_metadata()

    def save_metadata(self):
        (self.dist / 'windows-portable-provenance.json').write_text(
            json.dumps(self.metadata))

    def test_legacy_exact_inventory_still_passes(self):
        verify_candidate_inventory(self.dist, SOURCE)

    def test_current_complete_portable_evidence_passes_without_public_extras(self):
        self.portable()
        before = {p.name: p.read_bytes() for p in self.dist.iterdir()}
        verify_candidate_inventory(self.dist, SOURCE)
        stage_public_assets('2026.10.2-rc.4', self.dist, self.root / 'public')
        self.assertEqual({p.name for p in (self.root / 'public').iterdir()},
                         set(public_asset_names('2026.10.2-rc.4').values()))
        self.assertEqual({p.name: p.read_bytes() for p in self.dist.iterdir()}, before)

    def test_each_partial_portable_set_is_rejected(self):
        for missing in QA_FILES:
            with self.subTest(missing=missing):
                self.portable()
                saved = (self.dist / missing).read_bytes()
                (self.dist / missing).unlink()
                with self.assertRaises(ValueError):
                    verify_candidate_inventory(self.dist, SOURCE)
                (self.dist / missing).write_bytes(saved)

    def test_unknown_extra_is_rejected(self):
        (self.dist / 'unexpected.txt').write_text('extra')
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_missing_required_installer_is_rejected_with_portable_present(self):
        self.portable()
        (self.dist / 'tandemlog-windows-x64-unsigned-setup.exe').unlink()
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_wrong_source_archive_name_digest_and_payload_are_rejected(self):
        for key, value in (
                ('source_revision', 'b' * 40), ('github_run_id', 'invalid'),
                ('artifact', 'another.zip'), ('artifact_sha256', 'b' * 64),
                ('payload_sha256', {}), ('payload_sha256', {'tandemlog.exe': 'b' * 64})):
            with self.subTest(key=key):
                self.portable()
                self.metadata[key] = value
                self.save_metadata()
                with self.assertRaises(ValueError):
                    verify_candidate_inventory(self.dist, SOURCE)

    def test_changed_archive_and_checksum_are_rejected(self):
        self.portable()
        (self.dist / 'tandemlog-windows-x64-unsigned-portable.zip').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)
        self.portable()
        (self.dist / 'windows-portable-SHA256SUMS.txt').write_text('invalid\n')
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_unsafe_and_missing_required_payload_paths_are_rejected(self):
        for payload in ({'../tandemlog.exe': b'app'}, {'/tandemlog.exe': b'app'},
                        {'tandemlog.exe': b'app'}):
            with self.subTest(payload=payload):
                self.portable(payload)
                with self.assertRaises(ValueError):
                    verify_candidate_inventory(self.dist, SOURCE)

    def test_inventory_directory_and_symlink_are_rejected(self):
        target = self.dist / 'android-signature.txt'
        target.unlink()
        target.mkdir()
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)
        target.rmdir()
        outside = self.root / 'outside'
        outside.write_text('signer')
        target.symlink_to(outside)
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)


if __name__ == '__main__':
    unittest.main()
