# Exact candidate artifacts for parent native acceptance

Candidate [38027666368](https://github.com/reddraggone9/tandemlog/actions/runs/38027666368) and push CI [38027658576](https://github.com/reddraggone9/tandemlog/actions/runs/38027658576) both completed successfully for immutable executable source `97880eebf75875b1e83f2ce0039fb13f5c533968`, version `2026.10.4-rc.1+57`. These are original CI artifacts, materialized through supported resolved GitHub file references and the current Library transfer helper. No storage URL was guessed, no installer was rebuilt and no signing inputs were accessed. Artifact retention is five days.

| Platform | Artifact ID | Original member | Actual member SHA-256 |
| --- | --- | --- | --- |
| Android production | 11661298116 | `tandemlog-android.apk` | `e5cf44582e999dec3c6f5f57de5a3c89a458cb932e3e0bb12f35e026607f1078` |
| Windows installer | 11660613849 | `tandemlog-windows-x64-unsigned-setup.exe` | `2196693341d297e1f463dabb72dadad8b24a7adffddf482158327f1374d02e90` |
| Windows portable QA | 11660613849 | `tandemlog-windows-x64-unsigned-portable.zip` | `6a39b8cc257ae29db63c8d15c118bd9887a933b430fab3a42a0d55b84b1341ef` |
| Linux | 11661550518 | `tandemlog-linux-x64.flatpak` | `1c00c415d2ab0a1d19f74b12187754567cca48ccb0165c5fef206be051d46b40` |

Archive SHA-256 values: Android `d90416dee883c76325ea7628b0f74e7ad14d6b9ea3ab6d040a696b1f0a62e4a6`; Windows `754bc467b6015a924df8358d90871cff31e2709e87ef30693310d67f20d4230b`; Linux `fc5d9196b6795eff32a42ff2f9947b3438da7ee1ccf646f48fdd97471718565b`.

Actual APK verification passed using `apksigner`, `aapt`, frozen release metadata/checksum policy and the full native Android payload verifier. Package is `com.reddraggone9.tandemlog`, build 57, non-debuggable, with armeabi-v7a/arm64-v8a/x86_64 payloads and owner certificate SHA-256 `0a39694089338ce29d9b5407a58d16b819621c9697e15830679a4fee24d49b2d`. ELF alignment, native exports and exact packaged notices passed. This is byte verification on Linux, not Android installation or UI acceptance.

Actual hosted Linux logs record 822 app tests, 107 native/worker contracts, 57 policy tests and 92 native workflow tests passing. Actual hosted Windows logs record 819 app passes/two platform skips, required native ABI/payload checks and all four installed lifecycle phases passing. The portable 17-member inventory binds exact payload hashes to this source and run. Windows packaged notices have checkout CRLF; Unix source notices have LF. Independently reviewed content is equal after newline normalization; no raw cross-platform byte equality is claimed.

Linux install/real changed-commit upgrade/uninstall/reinstall passed with synthetic data, preserved permissions/payload and the final candidate restored. The original startup member contains a DBus stdout prefix before its final JSON object; original 6191 bytes remain unchanged. Its ten synthetic Tasks measured external readiness 1096ms for cache rebuild and 458ms warm, with OS page cache not flushed. These values do not establish general Food performance or a cold OS-cache result.

This replaces the failed source 2ec/f489 candidates because of unsafe native transaction-state access after a poisoned profile closed SQLite, a 26px long-error overflow at 390px/200% text, and a lazy disclosure test target requiring scroll discovery. The importer code, codecs, vectors and contract are unchanged from 2ec to 978. Historical diagnostics and their original attribution remain in earlier receipts. Private importer records are held by the parent and are excluded from this repository.

Parent acceptance of the exact Android and Windows artifacts under [the native contract](../../../../design/food-native-acceptance.md) remains required before preview publication. The operator must use this APK's actual SHA-256 for publication only after installation/launch and affected workflow QA pass. Debug Android, portable QA and diagnostic archives are not public installer substitutes. Stable promotion requires Lee's separate behavior-changing release approval. No live synced data was touched.

Reviewed release notes are pinned at documentation commit `360ec8aa6ddfd2ef9757fa5540aeb16737b94ae1`, SHA-256 `3e54e578fe650c863f282e16119cb17ebff71f8017953427d74999a0abe6c5ae`. Final source and actual stable-to-candidate notes/media reviews are retained one directory above. Evidence-only subsequent commits do not change executable source or these original artifact identities.

Final independent [full candidate/artifact review](corrected-full-candidate-artifacts-independent-review.json) accepted this completed candidate for parent native handoff with no must-fix findings. Actual APK signature/package checks, all 79 APK member CRCs and the combined 14-member original artifact inventory passed. This verdict does not attest device workflow acceptance or approve publication.
