"""Read and retain results before clearing only this invocation's exact units."""
import json
import re
import subprocess


def reset_owned(units, evidence, run=subprocess.run):
    saved = {}
    for unit in units:
        if not re.fullmatch(r'tandemlog-reference-[A-Za-z0-9_.@-]+', unit):
            raise ValueError('Not a reference unit')
        result = run(['/usr/bin/systemctl', 'show', unit, '-p', 'ActiveState', '-p',
                      'MainPID', '-p', 'Result', '-p', 'ExecMainStatus'],
                     capture_output=True, text=True, check=True, timeout=5)
        fields = dict(line.split('=', 1) for line in result.stdout.splitlines())
        if fields.get('ActiveState') not in ('inactive', 'failed') or fields.get('MainPID') != '0':
            raise ValueError('Owned unit is not inactive')
        saved[unit] = fields
    # Evidence is persisted before any reset, also on a failed qualification.
    with evidence.open('x') as f:
        json.dump(saved, f, indent=2)
    for unit in units:
        if saved[unit]['ActiveState'] == 'failed':
            run(['/usr/bin/systemctl', 'reset-failed', unit], check=True, timeout=5)
