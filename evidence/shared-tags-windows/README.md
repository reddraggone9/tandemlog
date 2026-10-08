# Shared tag Windows native gate

This isolated acceptance branch starts at reviewed shared-tag `d0349397`, whose
application/test/native inputs match tested `8b13cd0e`. The frozen checklist
candidate remains unchanged. It carries the already reviewed Windows receipt
runner and setup workflow from `50f12459` (production runner `7b6cd65e`), adds
the three shared-tag native workflows and retains all six earlier scope
definitions/counts. Their aggregate test file includes the separately reviewed
shared-tag key and Clear adaptations; the scoped search assertions retain their
strength. There are 22 expected actual Windows native debug flows.

The narrow runner changes add the tag scope, unset optional tag recording,
and update totals/descriptions and the scope-count fixture. Independent review
found no must-fix. All nine existing receipt tests pass, including zero-run,
skip/failure, absent startup, incomplete/empty payload and cp1252 controls.
No app/native/dependency/build-bootstrap change is introduced by this gate.

Actual Windows [run 37790261412](https://github.com/reddraggone9/tandemlog/actions/runs/37790261412)
at `ff1d1f82` passed all seven groups: 3 + 2 + 7 + 4 + 2 + 3 + 1 = 22.
The [decoded job log](job-113355485932.txt) and [qualified result](result.json)
were independently reviewed: numeric startup/readiness evidence accompanies
each group, with no skips or failures. Application/test/native inputs match
`8b13cd0e` byte for byte. The uploaded receipt archive's ID, size and digest
are reported metadata only; this consumer has not verified its bytes or
rehashed the actual Windows binary payloads.

A hosted pass establishes scripted debug
application behavior; it does not establish signed-release/manual visual,
assistive technology, Android IME/provider, overnight idle or physical display
acceptance. Receipt binary hashes are runner-reported; raw logs are uploaded,
and loaded-module enumeration is not performed.

Later test revision `ec2309db` changes three excluded legacy aggregate blocks
(two earlier 5204 interactions plus the guarded bulk Save interaction). The
whole aggregate file differs, but the selected workspace-search body and six
other entrypoints remain byte-identical, as do production/native/platform inputs.
This 22-flow run compiled `ff1d1f82`; new full CI 37796892998 remains pending.
