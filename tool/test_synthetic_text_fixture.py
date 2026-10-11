"""QA initialization invokes the pinned SDK executable across host platforms."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import synthetic_text_fixture as fixture


class SyntheticTextSdk(unittest.TestCase):
    def test_windows_batch_wrapper_resolves_actual_sdk_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            batch = root/'flutter/bin/dart.bat'
            sdk = batch.parent/'cache/dart-sdk/bin/dart.exe'
            batch.parent.mkdir(parents=True)
            sdk.parent.mkdir(parents=True)
            batch.write_bytes(b'synthetic wrapper')
            sdk.write_bytes(b'synthetic SDK')
            library = root/'tandemlog_text.dll'
            library.write_bytes(b'synthetic native path')
            receipt = {'synthetic': True, 'initialized': True}
            result = subprocess.CompletedProcess([], 0, json.dumps(receipt), '')
            with patch.object(fixture.shutil, 'which', return_value=str(batch)), \
                    patch.object(fixture.subprocess, 'run', return_value=result) as run:
                fixture.initialize_fixture(root/'shared', root, library)
            self.assertEqual(run.call_args.args[0][0], str(sdk.resolve()))
            self.assertNotEqual(run.call_args.args[0][0], str(batch))

    def test_missing_windows_sdk_fails_before_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            batch = root/'dart.bat'
            batch.write_bytes(b'synthetic wrapper')
            library = root/'tandemlog_text.dll'
            library.write_bytes(b'synthetic native path')
            with patch.object(fixture.shutil, 'which', return_value=str(batch)), \
                    patch.object(fixture.subprocess, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, 'SDK Dart executable is unavailable'):
                    fixture.initialize_fixture(root/'shared', root, library)
            run.assert_not_called()
            self.assertFalse((root/'text-seed-private').exists())

    def test_unavailable_pinned_toolchain_is_rejected(self):
        with patch.object(fixture.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'Pinned Dart executable is unavailable'):
                fixture.resolve_dart()


if __name__ == '__main__':
    unittest.main()
