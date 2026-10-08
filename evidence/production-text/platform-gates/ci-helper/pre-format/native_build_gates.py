"""Offline verification helpers for required native CI and packaged payloads."""
import argparse
import ctypes
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from build_text_engine import verify_elf, verify_pe, verify_exports, NDK_VERSION
RUSTUP_VERSION = '1.29.1'
RUSTUP_PINS = {
 'linux': ('x86_64-unknown-linux-gnu', 'rustup-init', 'dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71'),
 'windows': ('x86_64-pc-windows-msvc', 'rustup-init.exe', '6f4bef66261261fcb43131be8720bab817d403a09edec7455c371974b90bdb7e'),
}
NOTICE_PATH = 'native/text_engine/THIRD_PARTY_NOTICES.txt'

def verify_bootstrap(path, digest):
 if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError('Official rustup bootstrap checksum mismatch')

def verify_payload(platform, payload, notice):
 expected=notice.read_bytes()
 if platform=='android':
  with zipfile.ZipFile(payload) as z:
   for abi in ['arm64-v8a','armeabi-v7a','x86_64']:
    name=f'lib/{abi}/libtandemlog_text.so'
    if name not in z.namelist() or not z.read(name):raise ValueError(f'Missing packaged native library {name}')
   path='assets/flutter_assets/'+NOTICE_PATH
   if path not in z.namelist() or z.read(path)!=expected:raise ValueError('Missing or altered packaged native notices')
 else:
  lib=payload/('lib/libtandemlog_text.so' if platform=='linux' else 'tandemlog_text.dll')
  if not lib.is_file() or not lib.stat().st_size:raise ValueError(f'Missing packaged native library {lib}')
  path=payload/'data/flutter_assets'/NOTICE_PATH
  if not path.is_file() or path.read_bytes()!=expected:raise ValueError('Missing or altered packaged native notices')

def verify_native_library(path):
 """Actual ABI smoke before Flutter tests; cannot turn missing DLL into skip."""
 lib=ctypes.CDLL(str(path.resolve()));lib.tandemlog_text_json.argtypes=[ctypes.c_char_p];lib.tandemlog_text_json.restype=ctypes.c_void_p;lib.tandemlog_text_free.argtypes=[ctypes.c_void_p]
 def call(request):
  ptr=lib.tandemlog_text_json(json.dumps(request).encode())
  if not ptr:raise ValueError('Native ABI returned null')
  try:value=json.loads(ctypes.string_at(ptr))
  finally:lib.tandemlog_text_free(ptr)
  if 'error' in value:raise ValueError(value['error'])
  return value
 created=call({'op':'new','name':'ci-native-required','client':12301})
 if not isinstance(created.get('guid'),str) or created.get('client')!=12301:raise ValueError('Unexpected production native ABI identity')
 call({'op':'read','name':'ci-native-required'});call({'op':'cancel','name':'ci-native-required'})
 print('Required production native ABI loaded:',path)

def main():
 parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='op',required=True)
 lib=sub.add_parser('verify_library');lib.add_argument('library',type=Path)
 payload=sub.add_parser('verify_payload');payload.add_argument('--platform',required=True,choices=['linux','windows','android']);payload.add_argument('--payload',required=True,type=Path)
 args=parser.parse_args()
 if args.op=='verify_library':verify_native_library(args.library);return
 verify_payload(args.platform,args.payload,Path(__file__).resolve().parents[1]/NOTICE_PATH)
 if args.platform=='android':
  sdk=Path(os.environ['ANDROID_HOME']);ndk=sdk/'ndk'/NDK_VERSION;nm=ndk/'toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm'
  subprocess.run([str(sdk/'build-tools/36.0.0/zipalign'),'-c','-P','16','4',str(args.payload)],check=True)
  with tempfile.TemporaryDirectory() as t,zipfile.ZipFile(args.payload) as z:
   for abi,machine in [('arm64-v8a',183),('armeabi-v7a',40),('x86_64',62)]:
    lib=Path(t)/f'{abi}.so';lib.write_bytes(z.read(f'lib/{abi}/libtandemlog_text.so'));verify_elf(lib,machine,android=True);verify_exports(lib,nm,os.environ.copy())
 else:
  lib=args.payload/('lib/libtandemlog_text.so' if args.platform=='linux' else 'tandemlog_text.dll')
  if args.platform=='linux':verify_elf(lib,62);verify_exports(lib,shutil.which('nm'),os.environ.copy())
  else:verify_pe(lib)
  verify_native_library(lib)
 print('Packaged native library and exact notices verified:',args.payload)
if __name__=='__main__':main()
