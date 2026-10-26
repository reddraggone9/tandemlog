"""Independent Python canonical SHA-256 vectors; never edits old fixtures."""
import hashlib
import json
from pathlib import Path

DEST = Path(__file__).resolve().parents[2] / 'test/fixtures/completion-instant-v3'

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

space = '11111111-1111-4111-8111-111111111111'
writer = '22222222-2222-4222-8222-222222222222'
subject = '44444444-4444-4444-8444-444444444444'
epoch = '55555555-5555-4555-8555-555555555555'
head = digest(f'tandemlog:app-genesis:v5\n{space}\n{epoch}\n{writer}')
body = dict(format='tandemlog.operation', version=1, module='tasks',
            space=space, author=writer, identity=dict(writer=writer, sequence=1),
            clock='1793023445123456000', subject=subject,
            operation=dict(family='task.complete', revision=3),
            value=dict(mode='snapshot', values=dict(completedInstant='2026-10-26T15:24:05.123456Z')),
            predecessor=head)
hash_value = digest('tandemlog:operation:v1\n' + canonical(body))
op = dict(body, contentHash=hash_value, referenceHash=hash_value)
raw = canonical(op)
action = dict(v=5, space=space, epoch=epoch, writer=writer, seq=1,
              clock=body['clock'], previousHash=head,
              observed={writer: dict(seq=0, hash=head)},
              effects=[dict(kind='task', raw=raw)], provenance=None)
action['hash'] = digest('tandemlog:app-action:v5\n' + canonical(action))
DEST.mkdir(parents=True, exist_ok=True)
(DEST/'operation.json').write_text(raw + '\n')
(DEST/'action.json').write_text(canonical(action) + '\n')
(DEST/'README.md').write_text('New revision3 vectors, generated independently by tool/normalization/generate_completion_goldens.py using Python JSON and SHA256. Not an accepted performance fixture, old fixture rewrite, or valid complete workspace.\\n')
