"""Cache receipts and owning histories reject external Dart implementations."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ActionCacheBoundaryTests(unittest.TestCase):
    def test_receipts_cannot_be_implemented_outside_the_verifier(self):
        dart = shutil.which("dart")
        if not dart:
            self.skipTest("Dart SDK is required for the negative compiler control")
        cache_root = ROOT / ".dart_tool"
        cache_root.mkdir(exist_ok=True)
        library = (ROOT / "lib/domain/validated_action_cache.dart").as_uri()
        input_library = (ROOT / "lib/text/recurring_text.dart").as_uri()
        history_library = (ROOT / "lib/storage/unified_history.dart").as_uri()
        with tempfile.TemporaryDirectory(prefix="cache-boundary-", dir=cache_root) as folder:
            target = Path(folder) / "boundary.dart"
            target.write_text(
                "import '" + library + "';\n"
                "import '" + input_library + "';\n"
                "import '" + history_library + "';\n"
                "ValidatedActionEffect? echo(ValidatedActionEffect? value) => value;\n"
                "RecurringTextInput? echoInput(RecurringTextInput? value) => value;\n"
                "UnifiedHistory? echoHistory(UnifiedHistory? value) => value;\nvoid main() {}\n",
                encoding="utf-8",
            )
            def analyze():
                return subprocess.run(
                    [dart, "analyze", "--format=machine", str(target)],
                    cwd=ROOT, text=True, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, timeout=60,
                )
            valid = analyze()
            self.assertEqual(valid.returncode, 0, valid.stdout)
            for name in ("ValidatedActionEffect", "ValidatedCachedAction", "ValidatedActionCache", "RecurringTextInput", "UnifiedHistory"):
                with self.subTest(receipt=name):
                    target.write_text(
                        "import '" + library + "';\n"
                        "import '" + input_library + "';\n"
                        "import '" + history_library + "';\n"
                        "class Fake implements " + name + " {\n"
                        "  @override\n  dynamic noSuchMethod(Invocation invocation) => null;\n"
                        "}\nvoid main() {}\n",
                        encoding="utf-8",
                    )
                    rejected = analyze()
                    self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
                    self.assertIn(
                        "invalid_use_of_type_outside_library",
                        rejected.stdout.lower(), rejected.stdout,
                    )

if __name__ == "__main__":
    unittest.main()
