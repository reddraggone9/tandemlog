"""Frozen readers and canonical packets survive a Windows-style Git checkout."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = Path('test/fixtures/food-undo/released-build60')


class FoodFixtureCheckout(unittest.TestCase):
    def test_autocrlf_checkout_preserves_released_reader_and_packet_bytes(self):
        provenance = json.loads((ROOT / FIXTURE / 'provenance.json').read_text())
        files = [FIXTURE / entry['source'][4:] for entry in provenance['frozenFiles']]
        packet = Path('test/fixtures/food-undo/mixed-v1-v2.foodlog')
        with tempfile.TemporaryDirectory(prefix='food-fixture-checkout-') as directory:
            subprocess.run([
                'git', '-C', str(ROOT), '-c', 'core.autocrlf=true',
                'checkout-index', f'--prefix={Path(directory).as_posix()}/',
                '--', *(path.as_posix() for path in [*files, packet]),
            ], check=True, capture_output=True)
            for path, entry in zip(files, provenance['frozenFiles']):
                data = (Path(directory) / path).read_bytes()
                self.assertEqual(len(data), entry['bytes'], path.as_posix())
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry['sha256'])
            self.assertEqual((Path(directory) / packet).read_bytes(),
                             (ROOT / packet).read_bytes())


    def test_current_operation_golden_bytes_survive_windows_checkout(self):
        fixture = Path('test/fixtures/current-operation-v1')
        provenance = json.loads((ROOT/fixture/'provenance.json').read_text())
        files = [fixture/name for name in provenance['files']]
        files.append(fixture/'provenance.json')
        with tempfile.TemporaryDirectory(prefix='current-fixture-checkout-') as directory:
            subprocess.run([
                'git', '-C', str(ROOT), '-c', 'core.autocrlf=true',
                'checkout-index', f'--prefix={Path(directory).as_posix()}/',
                '--', *(path.as_posix() for path in files),
            ], check=True, capture_output=True)
            for name, metadata in provenance['files'].items():
                data=(Path(directory)/fixture/name).read_bytes()
                self.assertEqual(hashlib.sha256(data).hexdigest(),metadata['sha256'])
                self.assertEqual(data,(ROOT/fixture/name).read_bytes())
            self.assertEqual((Path(directory)/fixture/'provenance.json').read_bytes(),
                             (ROOT/fixture/'provenance.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
