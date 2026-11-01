import copy
import unittest
from update_channels import scoop_manifest, stable_asset, REPO


def release():
    name = 'tandemlog-2026.10.10-windows-x64-portable.zip'
    return {'id': 123, 'tag_name': 'v2026.10.10', 'draft': False, 'prerelease': False,
            'assets': [{'name': name, 'digest': 'sha256:' + 'a' * 64,
                        'browser_download_url': f'https://github.com/{REPO}/releases/download/v2026.10.10/{name}'}]}


class UpdateChannels(unittest.TestCase):
    def test_latest_only_and_exact_original_zip(self):
        r = release()
        m = scoop_manifest(r, copy.deepcopy(r))
        self.assertEqual(m['architecture']['64bit']['hash'], 'a' * 64)
        self.assertEqual(m['architecture']['64bit']['url'], r['assets'][0]['browser_download_url'])
        self.assertEqual(m['bin'], [['cli/bin/tandemlog-cli.exe', 'tandemlog-cli']])
        self.assertNotIn('persist', m)
        self.assertNotIn('env_set', m)
        self.assertNotIn('installer', m)
        for key, bad in [('id', 124), ('tag_name', 'v2026.10.11'), ('draft', True), ('prerelease', True)]:
            latest = copy.deepcopy(r)
            latest[key] = bad
            with self.assertRaises(ValueError):
                scoop_manifest(r, latest)

    def test_wrong_source_missing_digest_duplicate_asset_and_rc_refuse(self):
        r = release()
        for change in ['url', 'hash', 'duplicate', 'missing', 'rc']:
            bad = copy.deepcopy(r)
            if change == 'url': bad['assets'][0]['browser_download_url'] += '?other'
            if change == 'hash': bad['assets'][0].pop('digest')
            if change == 'duplicate': bad['assets'] *= 2
            if change == 'missing': bad['assets'] = []
            if change == 'rc': bad['tag_name'] = 'v2026.10.11-rc.1'
            with self.assertRaises(ValueError):
                stable_asset(bad, bad, 'windows-x64-portable.zip')


if __name__ == '__main__': unittest.main()
