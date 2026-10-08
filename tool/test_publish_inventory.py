import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch
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

    def test_actual_portable_producer_is_compatible(self):
        bundle = self.root / 'bundle'
        for name in ('tandemlog.exe', 'tandemlog_text.dll', 'flutter_windows.dll',
                     'data/flutter_assets/AssetManifest.bin'):
            path = bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(name.encode())
        with patch('sys.argv', ['package_portable', '--bundle', str(bundle),
                               '--output', str(self.dist), '--source-revision', SOURCE,
                               '--run-id', '123']):
            runpy.run_path(str(Path(__file__).resolve().parents[1]
                               / 'packaging/windows/package_portable.py'))['main']()
        verify_candidate_inventory(self.dist, SOURCE)

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
        for unsafe in ('../outside', '/outside', 'C:/outside', 'data\\outside',
                       'data/./outside', 'TANDEMLOG.EXE'):
            with self.subTest(unsafe=unsafe):
                self.portable()
                payload = {name: b'content' for name in self.metadata['payload_sha256']}
                payload[unsafe] = b'unsafe'
                self.portable(payload)
                with self.assertRaises(ValueError):
                    verify_candidate_inventory(self.dist, SOURCE)
        self.portable({'tandemlog.exe': b'app'})
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_member_digest_mismatch_is_rejected(self):
        self.portable()
        self.metadata['payload_sha256']['tandemlog.exe'] = 'b' * 64
        self.save_metadata()
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_archive_symlink_is_rejected_with_valid_source_and_digests(self):
        self.portable()
        archive = self.dist / self.metadata['artifact']
        with zipfile.ZipFile(archive) as zipped:
            payload = {name: zipped.read(name) for name in zipped.namelist()}
        with zipfile.ZipFile(archive, 'w') as zipped:
            for name, data in payload.items():
                member = zipfile.ZipInfo(name)
                member.external_attr = (0o120777 if name == 'tandemlog.exe'
                                        else 0o100644) << 16
                zipped.writestr(member, data)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.metadata['artifact_sha256'] = digest
        self.save_metadata()
        (self.dist / 'windows-portable-SHA256SUMS.txt').write_text(
            f'{digest}  {archive.name}\n')
        with self.assertRaises(ValueError):
            verify_candidate_inventory(self.dist, SOURCE)

    def test_non_object_provenance_is_rejected(self):
        self.portable()
        (self.dist / 'windows-portable-provenance.json').write_text('[]')
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
