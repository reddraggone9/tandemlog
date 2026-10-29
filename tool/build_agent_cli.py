"""Build the headless agent CLI into a self-contained bin/ + lib/ directory.

The layout is the same inside the Flatpak (/app/tandemlog-cli), the Windows
installer and the portable ZIP (<app>/cli): bin/tandemlog-cli[.exe] next to
lib/ holding SQLite (from Dart native assets) and the app's own reviewed text
engine, copied byte-for-byte. A headless smoke run (no display variables)
initializes a synthetic workspace, captures, lists, undoes and serves MCP.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dart_executable():
    dart = shutil.which('dart')
    if dart is None:
        raise SystemExit('Pinned Dart executable is unavailable')
    return dart


def build(root, platform, text_library, output):
    windows = platform == 'windows'
    with tempfile.TemporaryDirectory() as raw:
        subprocess.run([dart_executable(), 'build', 'cli', '--target',
                        'bin/tandemlog_cli.dart', '--output', raw],
                       cwd=root, check=True, shell=windows)
        bundle = Path(raw) / 'bundle'
        exe = bundle / 'bin' / ('tandemlog_cli.exe' if windows else 'tandemlog_cli')
        if not exe.is_file():
            raise SystemExit(f'Missing compiled CLI {exe}')
        sqlite = [p for p in (bundle / 'lib').iterdir()
                  if 'sqlite3' in p.name.lower()]
        if len(sqlite) != 1:
            raise SystemExit('Expected exactly one SQLite native asset')
        if output.exists():
            shutil.rmtree(output)
        (output / 'bin').mkdir(parents=True)
        (output / 'lib').mkdir()
        target = output / 'bin' / ('tandemlog-cli.exe' if windows else 'tandemlog-cli')
        shutil.copy2(exe, target)
        shutil.copy2(sqlite[0], output / 'lib' / sqlite[0].name)
    text_name = 'tandemlog_text.dll' if windows else 'libtandemlog_text.so'
    if text_library.name != text_name:
        raise SystemExit(f'Text library must be {text_name}')
    shutil.copy2(text_library, output / 'lib' / text_name)
    if not windows:
        target.chmod(0o755)
    return target


def run(cli, args, env, expect=0):
    result = subprocess.run([str(cli), *args, '--format', 'json'], env=env,
                            capture_output=True, text=True, timeout=120)
    out = result.stdout if result.returncode == 0 else result.stderr
    if result.returncode != expect:
        raise SystemExit(f'{args}: exit {result.returncode}: {result.stdout}{result.stderr}')
    return json.loads(out) if out.strip() else {}


def smoke(cli):
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        (root / 'ws').mkdir()
        env = {k: v for k, v in os.environ.items()
               if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'TANDEMLOG_PROFILE',
                            'TANDEMLOG_CLI_PROFILE')}
        env.update({'HOME': str(root), 'XDG_DATA_HOME': str(root / 'data'),
                    'APPDATA': str(root / 'appdata'), 'TZ': 'America/Chicago'})
        schema = subprocess.run([str(cli), 'schema'], env=env, capture_output=True,
                                text=True, check=True, timeout=60)
        commands = json.loads(schema.stdout)['commands']
        run(cli, ['init', '--workspace', str(root / 'ws'), '--name', 'Smoke',
                  '--create', '--tz', 'America/Chicago'], env)
        common = ['--tz', 'America/Chicago']
        run(cli, ['people', 'add', 'Smoke Person', *common], env)
        added = run(cli, ['tasks', 'add', 'Headless capture', '--for',
                          'Smoke Person', *common], env)
        task = added['affected'][0]
        listed = run(cli, ['tasks', 'list', *common], env)
        if listed['total'] != 1:
            raise SystemExit('Smoke capture is not listed')
        done = run(cli, ['tasks', 'complete', task['id'], '--if-rev', task['rev'],
                         *common], env)
        rev = done['affected'][0]['rev']
        run(cli, ['undo', done['actions'][0], f"--rev={task['id']}={rev}", *common],
            env)
        mcp = subprocess.run(
            [str(cli), 'mcp', '--tz', 'America/Chicago'], env=env, text=True,
            capture_output=True, timeout=120,
            input='\n'.join(json.dumps(m) for m in [
                {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                 'params': {'protocolVersion': '2025-06-18', 'capabilities': {},
                            'clientInfo': {'name': 'smoke', 'version': '1'}}},
                {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
                {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
                 'params': {'name': 'tasks_list', 'arguments': {}}},
            ]) + '\n')
        replies = [json.loads(line) for line in mcp.stdout.splitlines() if line]
        if len(replies) != 3 or replies[2]['result']['isError']:
            raise SystemExit(f'MCP smoke failed: {mcp.stdout}{mcp.stderr}')
        return {'commands': len(commands),
                'mcp_tools': len(replies[1]['result']['tools'])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['linux', 'windows'])
    parser.add_argument('--text-library', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--no-smoke', action='store_true')
    parser.add_argument('--smoke-only', type=Path,
                        help='Smoke an installed tandemlog-cli executable.')
    args = parser.parse_args()
    if args.smoke_only:
        print(json.dumps({'smoke': smoke(args.smoke_only)}, sort_keys=True))
        return
    if not (args.platform and args.text_library and args.output):
        parser.error('--platform, --text-library and --output are required')
    root = Path(__file__).resolve().parents[1]
    cli = build(root, args.platform, args.text_library.resolve(),
                args.output.resolve())
    receipt = {
        'payload_sha256': {p.relative_to(args.output).as_posix(): sha(p)
                           for p in sorted(args.output.rglob('*')) if p.is_file()},
    }
    if not args.no_smoke:
        receipt['smoke'] = smoke(cli)
    print(json.dumps(receipt, indent=2, sort_keys=True))


if __name__ == '__main__':
    sys.exit(main())
