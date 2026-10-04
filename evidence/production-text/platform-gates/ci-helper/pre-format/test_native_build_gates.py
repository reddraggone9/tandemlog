"""Production native CI/payload gate tests frozen before workflow integration."""
import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from native_build_gates import verify_payload, verify_bootstrap, RUSTUP_PINS
ROOT = Path(__file__).resolve().parents[1]
class NativeGates(unittest.TestCase):
 def test_bootstrap_hash_fail_closed(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'bootstrap';p.write_bytes(b'wrong')
   with self.assertRaisesRegex(ValueError,'checksum'):verify_bootstrap(p,RUSTUP_PINS['linux'][2])
   verify_bootstrap(p,hashlib.sha256(b'wrong').hexdigest())
 def test_desktop_notice_and_payload_presence(self):
  for platform,relative in [('linux','lib/libtandemlog_text.so'),('windows','tandemlog_text.dll')]:
   with tempfile.TemporaryDirectory() as t:
    root=Path(t);source=root/'notice';source.write_bytes(b'copyright');bundle=root/'bundle';bundle.mkdir()
    with self.assertRaisesRegex(ValueError,'library'):verify_payload(platform,bundle,source)
    lib=bundle/relative;lib.parent.mkdir(parents=True,exist_ok=True);lib.write_bytes(b'native')
    with self.assertRaisesRegex(ValueError,'notice'):verify_payload(platform,bundle,source)
    notice=bundle/'data/flutter_assets/native/text_engine/THIRD_PARTY_NOTICES.txt';notice.parent.mkdir(parents=True);notice.write_bytes(source.read_bytes());verify_payload(platform,bundle,source)
    notice.write_bytes(b'truncated')
    with self.assertRaisesRegex(ValueError,'notice'):verify_payload(platform,bundle,source)
 def test_apk_all_abis_and_exact_notice(self):
  with tempfile.TemporaryDirectory() as t:
   r=Path(t);notice=r/'notice';notice.write_bytes(b'copyright');apk=r/'app.apk'
   for missing in ['armeabi-v7a',None]:
    with zipfile.ZipFile(apk,'w') as z:
     z.writestr('assets/flutter_assets/native/text_engine/THIRD_PARTY_NOTICES.txt',notice.read_bytes())
     for abi in ['arm64-v8a','x86_64','armeabi-v7a']:
      if abi!=missing:z.writestr('lib/'+abi+'/libtandemlog_text.so',b'native')
    if missing:
     with self.assertRaisesRegex(ValueError,'library'):verify_payload('android',apk,notice)
    else:verify_payload('android',apk,notice)
 def test_all_build_paths_bootstrap_and_real_native_unit_env(self):
  action=(ROOT/'.github/actions/setup-text-engine/action.yml').read_text();self.assertIn('bootstrap_text_engine.py',action);self.assertIn('py -3.11',action)
  validate=(ROOT/'.github/workflows/validate.yml').read_text()
  for job in ['linux','windows','android']:
   section=validate.split('  '+job+':',1)[1].split('\n  ',1)[0] if False else validate.split('  '+job+':',1)[1]
   if job!='android':section=section.split('\n  '+('windows' if job=='linux' else 'android')+':',1)[0]
   self.assertIn('./.github/actions/setup-text-engine',section)
   if job!='android':
    self.assertIn('TANDEMLOG_TEXT_LIBRARY',section);self.assertLess(section.index('build_text_engine.py'),section.index('run: flutter test'))
   self.assertIn('verify_payload',section)
  candidate=(ROOT/'.github/workflows/android-candidate.yml').read_text();self.assertIn('./.github/actions/setup-text-engine',candidate);self.assertIn('verify_payload',candidate)
  self.assertIn('ndkVersion = "28.2.13676358"',(ROOT/'android/app/build.gradle.kts').read_text())
if __name__=='__main__':unittest.main()
