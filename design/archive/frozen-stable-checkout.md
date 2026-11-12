# Frozen stable-v3 checkout bytes (2026-10-26)

CI40403722043 Windows failed the unchanged frozen-replay test before replay:
`event.dart` provenance expected `16de7d402144fe86d5a6ea5e258cd071d526bada650303008a7e7632f636b498`,
but the checkout contained `f32692bbd10bb5d277667e625970f9404c0d38ccf689220bf292121b5613a517`.
The latter is exactly the SHA256 of the original LF source converted to CRLF.
The original provenance/golden is correct; Git checkout conversion is wrong.

Before changing attributes, reproduced the identical test/line/hash failure in
the RC checkout using Flutter3.47.5/Dart3.13.4 and only a CRLF-transformed copy of
the sealed event source. Restored that file directly from HEAD afterward.
A separate Git checkout with core.autocrlf=true reproduced the bad hash for all
six sealed reader sources. The new scoped -text attribute preserves all six
original hashes under the same checkout setting. The unchanged frozen-replay
Flutter test then passed. No accepted source, fixture, provenance, assertion or
application behavior was changed; no Windows native runtime test is claimed.

## Converted goldens (CI40422261050)

With the readers fixed, the same Windows test reached replay and failed:
`22222222-…applog: record 1, byte offset 0: Action hash or canonical bytes differ`.
The converted canonical goldens in `test/fixtures/completion-instant-v3/converted-stable-v3/*.applog`
were outside the `*.jsonl -text` rule. Converting only those two files to CRLF in a
Linux checkout reproduces the identical message with Flutter3.47.5. The fix marks
every `*.applog` fixture and both frozen stable-v3 fixture directories `-text`; a
core.autocrlf=true checkout then preserves every frozen stable-v3, `.applog` and
`.jsonl` fixture byte, and the unchanged frozen-replay and completion-instant tests
pass. Parsed JSON inputs under `food-import/` and `utf8-size-guards/` still convert
and already pass on Windows. No fixture, golden, assertion or application code changed.

Each attribute change alters the conservative reference source identity, so each
successor needs its own fresh enforcing qualification before CI.
