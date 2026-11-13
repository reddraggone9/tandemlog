"""Registration must track the committed action inventory and enforcing launcher."""
import ast
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RegistrationConsistency(unittest.TestCase):
    def test_current_registration_matches_limits_and_launcher(self):
        profile = json.loads((ROOT / 'tool/performance/reference-host-v1.json').read_text())
        limits = hashlib.sha256((ROOT / 'tool/performance/limits-v1.json').read_bytes()).hexdigest()
        self.assertEqual(profile['limitsSHA256'], limits)
        self.assertEqual(profile['toolHashes']['/tool/performance/limits-v1.json'], limits)
        tree = ast.parse((ROOT / 'tool/qualification/launch_reference.py').read_text())
        pins = {n.targets[0].id: ast.literal_eval(n.value) for n in tree.body
                if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Name)
                and n.targets[0].id in ('CONTROLLER_HASH', 'PRESSURE_HASH')}
        self.assertEqual(profile['controllerSHA256'], pins['CONTROLLER_HASH'])
        self.assertIn('limits_sha="' + limits + '"',
                      (ROOT / '.github/workflows/validate.yml').read_text())
