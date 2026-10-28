"""Launch the read-only waiter in a bounded Linux user-manager service, not shell &."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from wait_signed_candidate import arguments


def command(args):
    output = args.output.resolve()
    unit = 'tandemlog-candidate-wait-' + hashlib.sha256(str(output).encode()).hexdigest()[:16]
    script = Path(__file__).resolve().with_name('wait_signed_candidate.py')
    extra = (['--token-file', str(args.token_file.resolve())] if args.token_file else [])
    if args.direct_network:
        extra.append('--direct-network')
    return unit, ['systemd-run', '--user', '--unit=' + unit, '--service-type=exec',
                  '--property=RemainAfterExit=yes', '--property=KillMode=control-group',
                  '--property=TimeoutStopSec=10',
                  '--property=RuntimeMaxSec=' + str(args.timeout + 30),
                  '--property=StandardOutput=append:' + str(output / 'wait.log'),
                  '--property=StandardError=append:' + str(output / 'wait.log'),
                  sys.executable, '-u', str(script), '--repository', args.repository,
                  '--run-id', args.run_id, '--source', args.source, '--output', str(output),
                  '--timeout', str(args.timeout), '--command-timeout', str(args.command_timeout),
                  '--poll-interval', str(args.poll_interval), *extra]


def main(argv=None):
    args = arguments(argv)
    args.output.mkdir(parents=True, exist_ok=True)
    unit, launch = command(args)
    # Credential values are not serialized into argv, unit properties or logs.
    # Use gh's credential store; see the documented token-file option.
    subprocess.run(launch, check=True)
    print(json.dumps(dict(unit=unit, output=str(args.output.resolve()),
                          statusCommand=f'systemctl --user show {unit} '
                                        '-p ActiveState -p SubState -p Result -p ExecMainStatus')))
    return 0


if __name__ == '__main__':
    sys.exit(main())
