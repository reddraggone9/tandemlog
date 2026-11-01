import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

from flatpak_channel import ARCHIVE, PROVENANCE, REF, flatpakrepo, pack, sha256, site

SOURCE = 'a' * 40
VERSION = '2026.11.0'
TAG = f'v{VERSION}'
NAME = f'tandemlog-{VERSION}-linux-x64.flatpak'
FINGERPRINT = 'B' * 40


def release(digest, **changes):
    return {
        'id': 7, 'tag_name': TAG, 'draft': False, 'prerelease': False,
        'assets': [{
            'name': NAME, 'digest': f'sha256:{digest}',
            'browser_download_url': f'https://github.com/reddraggone9/tandemlog/releases/download/{TAG}/{NAME}',
        }],
        **changes,
    }


@unittest.skipUnless(shutil.which('ostree'), 'ostree required')
class FlatpakChannelTest(unittest.TestCase):
    """Real ostree, unsigned: no key may exist before Lee approves an identity."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        repo = self.root / 'repo'
        subprocess.run(['ostree', f'--repo={repo}', 'init', '--mode=archive'], check=True)
        tree = self.root / 'tree'
        tree.mkdir()
        (tree / 'file').write_text('synthetic')
        subprocess.run(['ostree', f'--repo={repo}', 'commit', f'--branch={REF}',
                        f'--tree=dir={tree}', '--subject=Synthetic'],
                       check=True, capture_output=True)
        self.repo = repo
        self.bundle = self.root / 'bundle.flatpak'
        self.bundle.write_bytes(b'bundle')
        self.packed = self.root / 'packed'
        pack(repo, self.bundle, SOURCE, self.packed)
        self.key = self.root / 'public.gpg'
        self.key.write_bytes(b'public-key-bytes')

    def run_site(self, rel=None, latest=None, archive=None):
        digest = hashlib.sha256(b'bundle').hexdigest()
        return site(archive or self.packed / ARCHIVE, self.packed / PROVENANCE,
                    rel or release(digest), latest or release(digest), self.key,
                    FINGERPRINT, self.root / 'site')

    def test_pack_records_exact_candidate(self):
        record = json.loads((self.packed / PROVENANCE).read_text())
        self.assertEqual(record['source'], SOURCE)
        self.assertEqual(record['bundleSha256'], sha256(self.bundle))
        self.assertEqual(record['archiveSha256'], sha256(self.packed / ARCHIVE))
        with self.assertRaises(FileExistsError):
            pack(self.repo, self.bundle, SOURCE, self.packed)
        with self.assertRaises(ValueError):
            pack(self.repo, self.bundle, 'main', self.root / 'other')

    def test_unsigned_repository_never_becomes_a_channel(self):
        with self.assertRaisesRegex(ValueError, 'Unsigned'):
            self.run_site()

    def test_other_bundle_and_prerelease_refuse(self):
        other = release('c' * 64)
        with self.assertRaisesRegex(ValueError, 'exact accepted'):
            self.run_site(other, other)
        digest = hashlib.sha256(b'bundle').hexdigest()
        with self.assertRaises(ValueError):
            self.run_site(release(digest, prerelease=True), release(digest))
        with self.assertRaises(ValueError):
            self.run_site(release(digest), release(digest, id=8))

    def test_changed_archive_refuses(self):
        changed = self.root / 'changed.tar'
        with tarfile.open(changed, 'w') as tar:
            tar.add(self.bundle, arcname='repo/file')
        with self.assertRaisesRegex(ValueError, 'exact accepted'):
            self.run_site(archive=changed)

    def test_repo_file_pins_key_and_fixed_url(self):
        text = flatpakrepo(b'key')
        self.assertIn('Url=https://reddraggone9.github.io/tandemlog/flatpak/repo/', text)
        self.assertIn('GPGKey=a2V5', text)
        self.assertIn('DefaultBranch=master', text)


if __name__ == '__main__':
    unittest.main()
