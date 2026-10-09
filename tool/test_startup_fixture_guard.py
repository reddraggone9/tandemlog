"""A benchmark must reject retained local/shared data before fixture writes."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class FreshFixture(unittest.TestCase):
    def test_existing_legacy_or_shared_state_is_retained(self):
        script=Path(__file__).resolve().parent/'measure_startup.py'
        for relative in ('profile/settings.json','shared/synthetic.jsonl'):
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as directory:
                file=Path(directory)/relative
                file.parent.mkdir()
                original=b'keep synthetic legacy bytes'
                file.write_bytes(original)
                result=subprocess.run([sys.executable,str(script),'--workspace',directory,'--tasks','1','--runs','1','--binary','/no-such-synthetic-binary'],capture_output=True,text=True)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(file.read_bytes(),original)
                self.assertIn('fresh',result.stderr)

if __name__=='__main__':
    unittest.main()
