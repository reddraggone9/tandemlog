"""Approved Yrs source identity and patch gates; entirely offline."""
import shutil
import tempfile
import unittest
from pathlib import Path

from build_text_engine import BuildError, ROOT, validate_crate


class VendoredYrsContracts(unittest.TestCase):
    def test_canonical_crate_uses_exact_approved_vendor(self):
        validate_crate(ROOT / 'native/text_engine')
        self.assertTrue((ROOT / 'native/text_engine/vendor/yrs-0.28.0/src/undo.rs').is_file())

    def test_source_mutation_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            crate = Path(directory) / 'engine'
            shutil.copytree(ROOT / 'native/text_engine', crate)
            source = crate / 'vendor/yrs-0.28.0/src/undo.rs'
            source.write_bytes(source.read_bytes() + b'\n// unexpected change\n')
            with self.assertRaisesRegex(BuildError, 'vendor'):
                validate_crate(crate)

    def test_missing_override_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            crate = Path(directory) / 'engine'
            shutil.copytree(ROOT / 'native/text_engine', crate)
            manifest = crate / 'Cargo.toml'
            manifest.write_text(manifest.read_text().split('[patch.crates-io]')[0])
            with self.assertRaisesRegex(BuildError, 'override'):
                validate_crate(crate)


if __name__ == '__main__':
    unittest.main()
