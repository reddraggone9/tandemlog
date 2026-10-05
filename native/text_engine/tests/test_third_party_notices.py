"""Offline locked-graph notice checks; no Cargo invocation or downloads."""
import hashlib
import json
from pathlib import Path
import re
import tomllib
import unittest

CRATE = Path(__file__).resolve().parents[1]


class LockedNotices(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (CRATE / 'THIRD_PARTY_NOTICES.txt').read_text()
        cls.audit = json.loads(cls.text.split('BEGIN AUDIT MANIFEST\n', 1)[1]
                              .split('\nEND AUDIT MANIFEST', 1)[0])
        cls.packages = {(p['name'], p['version']): p
                        for p in cls.audit['packages']}
        cls.blocks = dict(re.findall(
            r'^BEGIN LICENSE ([^\n]+)\n(.*?)^END LICENSE \1\n',
            cls.text, re.MULTILINE | re.DOTALL))

    def test_exact_locked_graph_and_checksums_are_covered(self):
        locked = tomllib.loads((CRATE / 'Cargo.lock').read_text())
        pins = {(p['name'], p['version']): p for p in locked['package']
                if 'source' in p or p['name'] == 'yrs'}
        self.assertEqual(set(pins), set(self.packages),
                         'Dependency changes require an explicit notice audit')
        for key, pin in pins.items():
            checksum = pin.get('checksum')
            if key == ('yrs', '0.28.0'):
                provenance = json.loads((CRATE / 'vendor/yrs-provenance.json').read_text())
                checksum = provenance['archiveSha256']
            self.assertEqual(checksum, self.packages[key]['checksum'])
            self.assertTrue(self.packages[key]['license'])

    def test_required_texts_are_present_and_untruncated(self):
        referenced = set()
        for package in self.packages.values():
            if package['targets']:
                self.assertTrue(package['notices'], package['name'])
            for notice in package['notices']:
                referenced.add(notice['id'])
                self.assertEqual(hashlib.sha256(
                    self.blocks[notice['id']].encode()).hexdigest(),
                    notice['sha256'], notice['id'])
        for notice in self.audit['toolchain']['notices']:
            referenced.add(notice['id'])
            self.assertEqual(hashlib.sha256(
                self.blocks[notice['id']].encode()).hexdigest(),
                notice['sha256'])
        self.assertEqual(referenced, set(self.blocks))

    def test_special_attribution_and_target_exclusions(self):
        unicode = self.packages[('unicode-ident', '1.0.26')]
        self.assertIn('AND Unicode-3.0', unicode['license'])
        self.assertTrue(any(n['id'].endswith('/LICENSE-UNICODE')
                            for n in unicode['notices']))
        parking = self.packages[('parking', '2.2.1')]
        self.assertTrue(any(n['id'].endswith('/LICENSE-THIRD-PARTY')
                            for n in parking['notices']))
        yrs = self.packages[('yrs', '0.28.0')]
        self.assertEqual(yrs['license'], 'MIT')
        self.assertIn('23b7f5693bbf9e7d26340c521ee8647f79bdfba2',
                      yrs['notices'][0]['source'])
        for author in ['Bartosz Sypytkowski', 'Kevin Jahns']:
            self.assertIn(author, self.blocks[yrs['notices'][0]['id']])
        self.assertFalse(self.packages[('r-efi', '6.0.0')]['targets'])
        for name in ['async-trait', 'rustversion', 'serde_derive',
                     'thiserror-impl', 'proc-macro2', 'quote', 'syn',
                     'unicode-ident']:
            record = next(p for p in self.packages.values() if p['name'] == name)
            self.assertEqual(record['classification'], 'host-build-only')

    def test_pinned_standard_library_full_attribution_is_included(self):
        toolchain = self.audit['toolchain']
        self.assertEqual(toolchain['version'], '1.99.0')
        self.assertEqual(toolchain['commit'],
                         'b940084d7eb6a299eb4bfeb8e34901bc051e7ac4')
        std = self.blocks[toolchain['notices'][0]['id']]
        self.assertIn('Copyright notices for The Rust Standard Library', std)
        self.assertIn('Permission is hereby granted', std)
        self.assertIn('Apache License', std)
        self.assertGreater(len(std), 1000000)


if __name__ == '__main__':
    unittest.main(verbosity=2)
