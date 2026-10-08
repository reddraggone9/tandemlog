# Combined Windows debug flows

Scoped run 37813474065/job 113435998223 passed the three tag workflows and the
historical checklist recompletion/Undo regression: 4/0, no skips. Compiled runner
source `a249af55d49148db0525abd7f713ee716900353b` differs from frozen e205 only
in four reviewed CI/runner route files; application, tests, native code, platform
build inputs, locks and version are exact e205. Architecture cleared dispatch;
the nine preserved runner contract checks passed.

Independent correctness review accepted actual counts/startup markers, source
identity, both log hashes and fresh GitHub run/artifact metadata. Literal decoded
Windows job-log UTF8/CRLF bytes are preserved. This is actual scripted hosted
Windows debug execution, not merely a cross-build. The separate full e205 matrix
passed all three platforms; its checks are intentionally skipped in this scope-only
run and are not replaced by this result.

Artifact 11565823346 is reported 8025 bytes with ZIP SHA256
`2b83a2627cea3a210cc3cacce0ac886defdd2ce88ae2b063b1eb7bde70047a77`.
No consumer ZIP/member/payload rehash, raw receipt member read, runtime module
enumeration, manual visual/assistive-technology or signed installed-release
acceptance is claimed. The [receipt](receipt.json) and [current QA handoff](../../../design/final-preview-debug-native-qa.md)
retain those limits. No candidate mutation, signing or publication occurred.
