"""External code cannot forge the resolver-only compact-cache capability."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ResolvedTextCapabilityTests(unittest.TestCase):
    def test_external_subtypes_cannot_supply_resolver_capabilities(self):
        dart = shutil.which('dart')
        if not dart:
            self.skipTest('Pinned Dart toolchain is not installed')
        root = Path(__file__).resolve().parents[1]
        fixture = Path(tempfile.mkdtemp(prefix='tandemlog-capability-'))
        for kind, body in {
            'implements': 'dynamic noSuchMethod(Invocation invocation) => null;',
            'extends': '''Forged({required super.context, required super.seed,
                required super.operations, required super.state, required super.text});
                @override SharedTextReference? get historyReference => null;''',
        }.items():
            with self.subTest(kind=kind):
                source = fixture / f'{kind}.dart'
                source.write_text(f'''import 'package:tandemlog/text/recurring_text.dart';
import 'package:tandemlog/text/shared_text_history.dart';
abstract class Forged {kind} ResolvedTextField {{ {body} }}
void main() {{}}
''', encoding='utf-8')
                result = subprocess.run([
                    dart, 'compile', 'kernel',
                    f'--packages={root / ".dart_tool/package_config.json"}',
                    f'--output={fixture / (kind + ".dill")}', str(source),
                ], capture_output=True, text=True, timeout=90, cwd=root)
                self.assertNotEqual(result.returncode, 0,
                    f'External {kind} compiled: resolver capability is forgeable')
                self.assertIn('ResolvedTextField', result.stderr)
                self.assertIn('outside of its library', result.stderr)


if __name__ == '__main__':
    unittest.main()
