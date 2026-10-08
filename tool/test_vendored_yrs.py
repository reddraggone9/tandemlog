"""Approved Yrs source identity and patch gates; entirely offline."""
import shutil
import subprocess
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

    def test_windows_style_checkout_preserves_approved_vendor_bytes(self):
        self.assertIsNotNone(shutil.which('git'), 'Git is required for the checkout gate')
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / 'repository'
            checkout = Path(directory) / 'checkout'
            crate = repository / 'native/text_engine'
            crate.mkdir(parents=True)
            checkout.mkdir()
            shutil.copyfile(ROOT / '.gitattributes', repository / '.gitattributes')
            for filename in ('Cargo.toml', 'Cargo.lock'):
                shutil.copyfile(ROOT / 'native/text_engine' / filename, crate / filename)
            shutil.copytree(ROOT / 'native/text_engine/vendor', crate / 'vendor')
            for arguments in (
                ['init', '--quiet'],
                ['-c', 'core.autocrlf=false', 'add', '--force', '.'],
                ['-c', 'core.autocrlf=true', 'checkout-index', '--all',
                 '--prefix=' + checkout.as_posix() + '/'],
            ):
                subprocess.run(['git', '-C', str(repository), *arguments], check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            # Validation covers the literal inventory and all 67 approved files.
            validate_crate(checkout / 'native/text_engine')
            # The original Windows failure remains a negative control. Accepting
            # platform-rewritten bytes would weaken the dependency audit.
            attributes = repository / '.gitattributes'
            attributes.write_text(attributes.read_text().replace(
                'native/text_engine/vendor/** -text', ''))
            converted = Path(directory) / 'converted'
            converted.mkdir()
            for arguments in (
                ['-c', 'core.autocrlf=false', 'add', '.gitattributes'],
                ['-c', 'core.autocrlf=true', 'checkout-index', '--all',
                 '--prefix=' + converted.as_posix() + '/'],
            ):
                subprocess.run(['git', '-C', str(repository), *arguments], check=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            with self.assertRaisesRegex(BuildError, 'inventory hash'):
                validate_crate(converted / 'native/text_engine')

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
