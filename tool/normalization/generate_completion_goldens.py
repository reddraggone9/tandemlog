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
(DEST/'README.md').write_text('New revision3 vectors generated independently by tool/normalization/generate_completion_goldens.py using Python JSON and SHA256. Bare operation/action vectors are not a complete workspace. converted-stable-v3 contains separately sealed synthetic converter output; conversion-report.json retains evidence outside canonical operations. No old fixture or accepted performance bytes are rewritten.\n')

# Separately versioned converter-output vectors for the unchanged stable-v3
# synthetic histories. This is not the private multi-format historical reader.
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
source_root = DEST.parent / 'stable-v3-2026.10.0'
converted_root = DEST / 'converted-stable-v3'
converted_root.mkdir(exist_ok=True)
source_bytes = {path.name: path.read_bytes() for path in sorted(source_root.glob('*.jsonl'))}
source_hashes = {name: hashlib.sha256(raw).hexdigest() for name, raw in source_bytes.items()}
# Independent inventory: frozen fixture creations3/4/5 provide these zones;
# no later schedule edit changes them before the three completions.
era_zones = {'66666666-6666-4666-8666-666666666666':'America/Chicago',
             '77777777-7777-4777-8777-777777777777':'UTC',
             '88888888-8888-4888-8888-888888888888':'UTC'}
owners = {}
report = []
for name, source in source_bytes.items():
    events = [json.loads(line) for line in source.decode().splitlines()]
    writer = events[0]['writer']
    semantic_head = digest(f'tandemlog:genesis:v3\n{space}\n{writer}\n')
    physical_head = digest(f'tandemlog:app-genesis:v5\n{space}\n{epoch}\n{writer}')
    output = []
    for event in events:
        kind = event['type']
        data = dict(event['data'])
        revision = 1
        if kind == 'user.created': family, value = 'person.create', data
        elif kind == 'task.created': family, value = 'task.create', dict(values=data)
        elif kind == 'task.edited':
            family = 'task.update'
            value = dict(values={k:v for k,v in data.items() if k != 'tagChanges'})
            if 'tagChanges' in data: value['tags'] = data['tagChanges']
        elif kind == 'task.completed':
            family, revision = 'task.complete', 3
            recorded = data.pop('completedAt')
            zone = era_zones[event['entity']]
            # Original semantic clocks are on2026-02-01, not the recorded day;
            # independently require the specified noon fallback for these inputs.
            clock_instant = datetime.fromtimestamp(int(event['clock'])//1000/1e6, timezone.utc)
            assert clock_instant.astimezone(ZoneInfo(zone)).date().isoformat() != recorded
            instant = datetime.fromisoformat(recorded).replace(hour=12,tzinfo=ZoneInfo(zone)).astimezone(timezone.utc).isoformat(timespec='microseconds').replace('+00:00','Z')
            data['completedInstant'] = instant
            value = dict(mode='snapshot', values=data)
            report.append(dict(reference=f"{writer}:{event['seq']}", recordedDay=recorded, evidencedZone=zone, method='noon', instant=instant))
        elif kind in ('task.completionUndone','task.recurringCompletionUndone','task.operationUndone'):
            family = 'task.retract'
            mode = {'task.completionUndone':'completion','task.recurringCompletionUndone':'recurrence','task.operationUndone':'operation'}[kind]
            value = dict(mode=mode,reference=data['operation' if mode == 'operation' else 'completion'])
        elif kind in ('task.moved','task.deleted'): family, value = ('task.move' if kind == 'task.moved' else 'task.delete'),data
        else: raise AssertionError(kind)
        op_body = dict(format='tandemlog.operation', version=1, module='tasks',space=space,author=writer,
            identity=dict(writer=writer,sequence=event['seq']),clock=event['clock'],subject=event['entity'],
            operation=dict(family=family,revision=revision),value=value,predecessor=semantic_head)
        content_hash = digest('tandemlog:operation:v1\n'+canonical(op_body))
        op = dict(op_body,contentHash=content_hash,referenceHash=event['hash'])
        # Logical predecessor/reference continuity remains ORIGINAL, separately
        # from regenerated normalized content and physical action hashes.
        semantic_head = event['hash']
        action = dict(v=5,space=space,epoch=epoch,writer=writer,seq=event['seq'],clock=event['clock'],previousHash=physical_head,
            observed={},effects=[dict(kind='history.task',raw=canonical(op))],provenance=None)
        physical_head=digest('tandemlog:app-action:v5\n'+canonical(action))
        output.append(canonical(dict(action,hash=physical_head))+'\n')
    raw=''.join(output).encode()
    (converted_root/f'{writer}.applog').write_bytes(raw)
    owners[writer]=dict(count=len(output),head=physical_head,digest=hashlib.sha256(raw).hexdigest())
manifest=dict(v=5,id=space,epoch=epoch,sourceDigest=digest(canonical(dict(recipe='completion-instant-v3-synthetic-UTC-default-v1',sources=source_hashes))),
    owners=owners,referenceAuthors={writer:writer for writer in owners})
(converted_root/'tandemlog-space.json').write_text(canonical(manifest))
(DEST/'conversion-report.json').write_text(json.dumps(dict(syntheticOnly=True,sourceHashes=source_hashes,completions=report),indent=2)+'\n')
