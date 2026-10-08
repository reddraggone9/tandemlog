# Exact combined RC4 CI

Source `e205e650b5614935a73cf5acb96ca9b36fda8e4e` remains frozen and clean.
Run 37810677866 completed successfully on Linux, Windows and Android. The receipt
records exact source/job bindings, test counts, artifact API metadata and hosted
payload hashes. Independent correctness, security and architecture reviews
accepted this evidence and its limitations; no must-fix remains.

All three retained logs are exact UTF8 bytes of decoded MCP job-log content,
including Windows CRLF. They are not downloaded raw-log archive bytes.
Scoped `.gitattributes` prevents checkout line-ending conversion of this evidence.
Reviewers rehashed all three files and independently checked completed run/API
artifact metadata. Linux 628 unit/70 actual native, Windows 626 unit/two named
Linux-only skips, and each desktop's 4 Cargo/107 native/37 tool results are supported.
Release packaging, native payload/notices and installation lifecycle/smoke gates
completed successfully. Manual or signed installed-artifact acceptance is separate.

The Android connector returned a resolved file reference; current Library
preparation succeeded but supported consumer materialization returned 403. Outer
artifact digests are API-reported; member/certificate/payload hashes are hosted
log output. No consumer archive/member byte or signer verification is claimed.
The new debug signer differs from the isolated fix; preserve that ongoing A16
retest and its profile. See [the exact QA handoff](../../../design/final-preview-debug-native-qa.md).

Reviewed notes/media remain on separate `docs/rc4-release-notes`, with no candidate
mutation. Neither main integration, signing nor publication has occurred. Parent
isolated regression acceptance, consumer artifacts, final signed/native/manual/UX
acceptance, fresh quota and actual final-range editorial confirmation remain gates.
Stable feature promotion is not authorized.
