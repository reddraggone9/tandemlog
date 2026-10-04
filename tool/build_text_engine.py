"""Build the one locked Rust text engine; never install or fetch build inputs.

Bootstrap outside app builds with official rustup 1.99.0, the three Android
standard-library targets, and `cargo +1.99.0 fetch --locked` in native/text_engine.
The approved NDK must already exist. Caches default to OS temporary storage;
TANDEMLOG_TEXT_TARGET_DIR or --target-dir overrides the compiled output location.
"""
import argparse
import hashlib
import json
import os
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

RUST_VERSION = '1.99.0'
NDK_VERSION = '28.2.13676358'
ROOT = Path(__file__).resolve().parents[1]
ANDROID_TARGETS = {
    'arm64-v8a': ('aarch64-linux-android', 'aarch64-linux-android', 183),
    'x86_64': ('x86_64-linux-android', 'x86_64-linux-android', 62),
    'armeabi-v7a': ('armv7-linux-androideabi', 'armv7a-linux-androideabi', 40),
}
EXPORTS = ('tandemlog_text_json', 'tandemlog_text_free',
           'tandemlog_text_alloc', 'tandemlog_text_release_input')


class BuildError(RuntimeError):
    pass


def validate_crate(crate):
    for filename in ('Cargo.toml', 'Cargo.lock'):
        if not (crate / filename).is_file():
            raise BuildError(f'Missing canonical engine {crate / filename}')
    manifest = tomllib.loads((crate / 'Cargo.toml').read_text())
    library = manifest.get('lib', {})
    if library.get('name') != 'tandemlog_text' or 'cdylib' not in library.get('crate-type', []):
        raise BuildError('Canonical engine must declare lib tandemlog_text as cdylib')
    lock = tomllib.loads((crate / 'Cargo.lock').read_text())
    yrs = [entry for entry in lock.get('package', []) if entry.get('name') == 'yrs']
    if len(yrs) != 1 or yrs[0].get('version') != '0.28.0':
        raise BuildError('Canonical Cargo.lock must resolve yrs 0.28.0')


def validate_ndk(ndk):
    properties = ndk / 'source.properties'
    if not properties.is_file():
        raise BuildError(f'Missing approved Android NDK {NDK_VERSION}: {ndk}')
    values = {key.strip(): value.strip() for key, value in
              (line.split('=', 1) for line in properties.read_text().splitlines() if '=' in line)}
    if values.get('Pkg.Revision') != NDK_VERSION:
        raise BuildError(f'Android NDK must be exactly {NDK_VERSION}')


def verify_elf(library, machine, android=False):
    data = library.read_bytes()
    if len(data) < 52 or data[:4] != b'\x7fELF' or data[5] != 1:
        raise BuildError(f'Invalid little-endian ELF library: {library}')
    if struct.unpack_from('<HH', data, 16) != (3, machine):
        raise BuildError(f'Incorrect shared-library architecture: {library}')
    if not android:
        return
    if data[4] == 2 and len(data) >= 64:
        offset = struct.unpack_from('<Q', data, 32)[0]
        stride, count = struct.unpack_from('<HH', data, 54)
        minimum, alignment_offset, alignment_format = 56, 48, '<Q'
    elif data[4] == 1:
        offset = struct.unpack_from('<I', data, 28)[0]
        stride, count = struct.unpack_from('<HH', data, 42)
        minimum, alignment_offset, alignment_format = 32, 28, '<I'
    else:
        raise BuildError('Invalid ELF class/header')
    if stride < minimum or count == 0 or offset + stride * count > len(data):
        raise BuildError('Invalid ELF program header table')
    load_segments = 0
    for index in range(count):
        position = offset + index * stride
        if struct.unpack_from('<I', data, position)[0] == 1:
            load_segments += 1
            alignment = struct.unpack_from(alignment_format, data, position + alignment_offset)[0]
            if alignment < 16384:
                raise BuildError('Android load segments must support 16 KiB page alignment')
    if not load_segments:
        raise BuildError('ELF has no load segments')


def run(arguments, env, capture=False):
    try:
        result = subprocess.run(arguments, env=env, check=True, text=True,
                                stdout=subprocess.PIPE if capture else None)
        return result.stdout if capture else None
    except (OSError, subprocess.CalledProcessError) as error:
        raise BuildError(f'Native text build command failed: {arguments[0]} ({error})') from error


def verify_exports(library, nm, env):
    if not nm:
        raise BuildError('A native nm tool is required to verify the text engine ABI')
    symbols = run([str(nm), '--dynamic', '--defined-only', str(library)], env, capture=True)
    names = {line.split()[-1] for line in symbols.splitlines() if line.split()}
    missing = set(EXPORTS) - names
    if missing:
        raise BuildError(f'Missing text engine exports: {sorted(missing)}')


def verify_pe(library):
    """Inspect PE architecture and exported names without executing the DLL."""
    data = library.read_bytes()
    try:
        if data[:2] != b'MZ':
            raise BuildError('Invalid Windows DLL header')
        pe = struct.unpack_from('<I', data, 60)[0]
        machine, sections = struct.unpack_from('<HH', data, pe + 4)
        if data[pe:pe + 4] != b'PE\0\0' or machine != 0x8664:
            raise BuildError('Windows text engine must be a native x64 PE DLL')
        optional_size, characteristics = struct.unpack_from('<HH', data, pe + 20)
        optional = pe + 24
        if not characteristics & 0x2000 or struct.unpack_from('<H', data, optional)[0] != 0x20b:
            raise BuildError('Windows text engine must be a PE32+ DLL')
        table = optional + optional_size

        def rva_offset(rva):
            for index in range(sections):
                position = table + index * 40
                virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from('<IIII', data, position + 8)
                if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
                    offset = raw_offset + rva - virtual_address
                    if offset >= len(data):
                        break
                    return offset
            raise BuildError('Invalid PE export RVA')

        export_rva = struct.unpack_from('<I', data, optional + 112)[0]
        exports = rva_offset(export_rva)
        count = struct.unpack_from('<I', data, exports + 24)[0]
        names_rva = struct.unpack_from('<I', data, exports + 32)[0]
        names_offset = rva_offset(names_rva)
        names = set()
        for index in range(count):
            name_rva = struct.unpack_from('<I', data, names_offset + index * 4)[0]
            position = rva_offset(name_rva)
            end = data.index(b'\0', position)
            names.add(data[position:end].decode('ascii'))
        if set(EXPORTS) - names:
            raise BuildError(f'Missing Windows text engine exports: {sorted(set(EXPORTS) - names)}')
    except (struct.error, ValueError, UnicodeDecodeError) as error:
        raise BuildError(f'Invalid Windows DLL metadata: {library}') from error


def build(args):
    crate = ROOT / 'native' / 'text_engine'
    validate_crate(crate)
    rustup = shutil.which('rustup')
    if not rustup:
        raise BuildError('Official rustup with Rust 1.99.0 must be bootstrapped before app builds')
    env = os.environ.copy()
    env['RUSTUP_AUTO_INSTALL'] = '0'
    prefix = [rustup, 'run', RUST_VERSION]
    version = run(prefix + ['rustc', '--version'], env, capture=True).strip()
    if not version.startswith('rustc 1.99.0 '):
        raise BuildError(f'Rust must be exactly 1.99.0, observed {version}')
    if args.platform == 'linux':
        if sys.platform != 'linux' or platform.machine().lower() not in ('x86_64', 'amd64'):
            raise BuildError('Linux packaging currently requires a native x64 Linux host')
        targets = [('linux-x64', 'x86_64-unknown-linux-gnu', None, 62)]
        filename = 'libtandemlog_text.so'
    elif args.platform == 'windows':
        if sys.platform != 'win32' or platform.machine().lower() not in ('x86_64', 'amd64'):
            raise BuildError('Windows packaging requires a native x64 Windows MSVC host')
        targets = [('windows-x64', 'x86_64-pc-windows-msvc', None, None)]
        filename = 'tandemlog_text.dll'
    else:
        sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        ndk = args.ndk or (Path(sdk) / 'ndk' / NDK_VERSION if sdk else None)
        if ndk is None:
            raise BuildError('Supply --ndk or an Android SDK containing NDK 28.2.13676358')
        validate_ndk(ndk)
        host_tag = {'linux': 'linux-x86_64', 'darwin': 'darwin-x86_64'}.get(sys.platform)
        if host_tag is None:
            raise BuildError('Android Rust packaging currently supports Linux/macOS NDK hosts')
        toolchain = ndk / 'toolchains' / 'llvm' / 'prebuilt' / host_tag / 'bin'
        targets = [(abi, target, toolchain / f'{clang_target}24-clang', machine)
                   for abi, (target, clang_target, machine) in ANDROID_TARGETS.items()]
        filename = 'libtandemlog_text.so'
    for _, target, linker, _ in targets:
        libdir = Path(run(prefix + ['rustc', '--print', 'target-libdir', '--target', target], env, capture=True).strip())
        if not libdir.is_dir():
            raise BuildError(f'Missing official Rust 1.99.0 target {target}; bootstrap before app builds')
        if linker is not None and not linker.is_file():
            raise BuildError(f'Missing NDK API24 linker {linker}')
    cache_key = hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    target_dir = (args.target_dir or Path(env.get('TANDEMLOG_TEXT_TARGET_DIR') or
                  str(Path(tempfile.gettempdir()) / 'tandemlog-text-engine' / cache_key))).resolve()
    metadata = {'rust': version, 'crate': 'native/text_engine', 'platform': args.platform,
                'library': 'tandemlog_text', 'yrs': '0.28.0', 'exports': list(EXPORTS),
                'cargo_lock_sha256': hashlib.sha256((crate / 'Cargo.lock').read_bytes()).hexdigest(),
                'artifacts': []}
    if args.platform == 'android':
        metadata.update(ndk=NDK_VERSION, android_min_api=24, elf_page_alignment=16384)
    for abi, target, linker, machine in targets:
        target_env = env.copy()
        if linker is not None:
            target_env[f'CARGO_TARGET_{target.upper().replace("-", "_")}_LINKER'] = str(linker)
            flags = '-C\x1flink-arg=-Wl,-z,max-page-size=16384'
            prior_flags = target_env.get('CARGO_ENCODED_RUSTFLAGS')
            if prior_flags:
                flags = prior_flags + '\x1f' + flags
            elif target_env.get('RUSTFLAGS'):
                raise BuildError('Use CARGO_ENCODED_RUSTFLAGS rather than ambiguous Android RUSTFLAGS')
            target_env['CARGO_ENCODED_RUSTFLAGS'] = flags
        run(prefix + ['cargo', 'build', '--manifest-path', str(crate / 'Cargo.toml'),
                      '--release', '--locked', '--offline', '--target', target,
                      '--target-dir', str(target_dir)], target_env)
        library = target_dir / target / 'release' / filename
        if not library.is_file():
            raise BuildError(f'Cargo did not produce required library {library}')
        if machine is not None:
            verify_elf(library, machine, android=args.platform == 'android')
            nm = toolchain / 'llvm-nm' if args.platform == 'android' else shutil.which('nm')
            verify_exports(library, nm, target_env)
        else:
            verify_pe(library)
        destination = args.output_dir / abi / filename if args.platform == 'android' else args.output_dir / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(destination.suffix + '.tmp')
        shutil.copyfile(library, temporary)
        temporary.replace(destination)
        metadata['artifacts'].append({'abi': abi, 'target': target, 'path': str(destination),
                                     'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / 'text-engine-build.json').write_text(json.dumps(metadata, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', required=True, choices=('linux', 'windows', 'android'))
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--target-dir', type=Path)
    parser.add_argument('--ndk', type=Path)
    args = parser.parse_args()
    try:
        build(args)
    except (BuildError, OSError, ValueError) as error:
        print(f'Text engine packaging failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
