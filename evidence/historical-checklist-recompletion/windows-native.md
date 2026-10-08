# Focused Windows historical checklist app gate

This isolated branch starts at reviewed fix
`d73662ab8479aa8076ee04a5ed5badd1542e585d`. Application, test, native, platform
and dependency inputs remain unchanged. It carries the reviewed receipt runner
and two workflows from `50f12459ab32c65715665a188ddf7a47cc281cf5` solely
to execute the new historical checklist app regression on actual hosted Windows.
The historical runner provenance is verified against that local source checkpoint.

Runner changes are only the one-entry scope and expected total1; the nine receipt
tests retain startup/count/skip/failure/payload/encoding safeguards and pass locally.
Workflow input and step descriptions reflect the focused scope. It uses the
existing pinned Windows image, Flutter/Rust setup and actions. No app or dependency
change is introduced. Full CI is the separate exact-source run37804634954.

Expected native gate: completion consent, own successor task/item edits, offline
completion delivery, old-item edit, reopen/recomplete preservation and global Undo.
Actual Windows test success and retained job/startup/payload receipts are pending.
Hosted scripted debug execution is not signed-release/manual visual, accessibility,
Android provider/IME or loaded-module enumeration acceptance. No profile export.
