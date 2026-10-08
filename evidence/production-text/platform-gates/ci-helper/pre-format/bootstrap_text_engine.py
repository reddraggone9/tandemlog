"""CI-only official bootstrap; app build helper remains locked and offline."""
import argparse
import os
import subprocess
import urllib.request
from pathlib import Path
from native_build_gates import RUSTUP_PINS, RUSTUP_VERSION, verify_bootstrap
from build_text_engine import RUST_VERSION, ANDROID_TARGETS

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--platform',required=True,choices=['linux','windows','android']);args=parser.parse_args()
 host='windows' if os.name=='nt' else 'linux';triple,filename,digest=RUSTUP_PINS[host]
 directory=Path(os.environ['RUNNER_TEMP'])/'tandemlog-rust-bootstrap';directory.mkdir(exist_ok=True)
 installer=directory/filename;url=f'https://static.rust-lang.org/rustup/archive/{RUSTUP_VERSION}/{triple}/{filename}'
 with urllib.request.urlopen(url,timeout=60) as source:installer.write_bytes(source.read())
 verify_bootstrap(installer,digest)
 if host=='linux':installer.chmod(0o700)
 env=os.environ.copy();env.update(CARGO_HOME=str(directory/'cargo'),RUSTUP_HOME=str(directory/'rustup'),RUSTUP_UPDATE_ROOT='https://static.rust-lang.org/rustup',RUSTUP_DIST_SERVER='https://static.rust-lang.org',RUSTUP_AUTO_INSTALL='0')
 def run(command):subprocess.run([str(x) for x in command],env=env,check=True)
 run([installer,'-y','--no-modify-path','--profile','minimal','--default-toolchain','none'])
 rustup=Path(env['CARGO_HOME'])/'bin'/('rustup.exe' if host=='windows' else 'rustup')
 run([rustup,'set','auto-self-update','disable']);run([rustup,'toolchain','install',RUST_VERSION,'--profile','minimal'])
 targets=[item[0] for item in ANDROID_TARGETS.values()] if args.platform=='android' else [triple]
 run([rustup,'target','add','--toolchain',RUST_VERSION,*targets])
 run([rustup,'run',RUST_VERSION,'cargo','fetch','--locked','--manifest-path',Path(__file__).resolve().parents[1]/'native/text_engine/Cargo.toml'])
 with open(os.environ['GITHUB_ENV'],'a') as f:
  for key in ['CARGO_HOME','RUSTUP_HOME','RUSTUP_UPDATE_ROOT','RUSTUP_DIST_SERVER','RUSTUP_AUTO_INSTALL']:f.write(f'{key}={env[key]}\n')
  f.write(f'TANDEMLOG_TEXT_TARGET_DIR={directory / "target"}\n')
 with open(os.environ['GITHUB_PATH'],'a') as f:f.write(str(Path(env['CARGO_HOME'])/'bin')+'\n')
if __name__=='__main__':main()
