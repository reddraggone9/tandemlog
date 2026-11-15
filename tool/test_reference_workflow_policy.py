"""Release safety boundary: development reports never disable candidate gates."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class ReferenceWorkflowPolicyTest(unittest.TestCase):
    def test_development_advisory_and_candidate_required(self):
        workflows = ROOT / ".github/workflows"
        validation = (workflows / "validate.yml").read_text()
        policy = validation.split("      require_reference_performance:\n", 1)[1].split("      performance_calibration:", 1)[0]
        self.assertIn("default: true", policy)
        self.assertIn("require_reference_performance: false", (workflows / "ci.yml").read_text())
        self.assertIn("require_reference_performance: true", (workflows / "android-candidate.yml").read_text())
        reference = validation.split("  reference-performance:\n", 1)[1]
        self.assertEqual(reference.count("continue-on-error: ${{ !inputs.require_reference_performance }}"), 2)
        self.assertNotIn("    continue-on-error:", reference.replace("        continue-on-error:", ""))
        self.assertIn("steps.reference-receipt.outcome", reference)
        self.assertIn("steps.cold-start-receipt.outcome", reference)
        self.assertIn("reference_receipt.py verify", reference)
        self.assertIn("native_cold_start.py verify", reference)
        self.assertNotIn("continue-on-error: true", reference)
        self.assertIn("if: ${{ !cancelled() }}", reference)


if __name__ == "__main__":
    unittest.main()
