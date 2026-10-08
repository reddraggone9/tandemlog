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

Actual native gate: completion consent, own successor task/item edits, offline
completion delivery, old-item edit, reopen/recomplete preservation and global Undo.
Run37805503087 at exact `bcbcece5dc34d44dbb7453fa54c0882a3dbacd10`
passed1/0 with no skips on hosted Windows; job113408581947 reports first-frame300ms
and readiness1021ms. The [decoded job log](windows-native-job-113408581947.txt)
and [receipt](windows-native-receipt.json) preserve source/count/startup binding.
Artifact11563525981,6509bytes,SHA256
`af2842160d4783020c0847437e9cd2b5c4d30cb3710cafbffcbf9634f70dba28`
is API/host-reported only; consumer archive/binary rehash is not claimed.
Hosted scripted debug execution is not signed-release/manual visual, accessibility,
Android provider/IME or loaded-module enumeration acceptance. No profile export.
