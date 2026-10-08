# Scoped Windows debug application result

Run 37754442151, job 113235408884, exact tested source
`7b6cd65ed7db8ff8b5025abacba503e5c2f812c3`, completed successfully on
2026-10-08 at 09:14:52 UTC. Windows Server 2022 image 20261004.326.1,
Python 3.11.9, existing pinned Flutter 3.47.5 and Rust 1.99.0/MSVC setup were used.
The ordinary full-CI job was skipped as intended for this explicit manual mode.
Application, native, integration-test and dependency inputs match candidate
`a960c882c06c018a1e721e7459f08dbe4d17bed3`.

| Native entrypoint | Passed | Command exit | Command seconds | First-frame ms | Readiness ms |
| --- | ---: | ---: | ---: | --- | --- |
| Checklist workflow | 2 | 0 | 147.969 | 211,27 | READY 832,340 |
| Checklist lifecycle | 7 | 0 | 43.281 | 212,22,21,17,21,20,17,17,16 | READY 822,200,380,209,325,354,370,349,351 |
| Inbox | 4 | 0 | 30.969 | 178,26,24,20 | ONBOARDING_READY 725; READY 563,316 |
| Bulk apply semantics | 2 | 0 | 30.672 | 194,24 | READY 780,331 |
| Field layout | 3 | 0 | 36.297 | 196,24,25 | READY 847,398,358 |
| Exact workspace-search filter | 1 | 0 | 31.313 | 190 | READY 808 |

Total 19 tests passed with no skips/failures. Counts are test totals, not startup
totals: fixture reloads can emit several startup markers within one test.
The six retained raw logs match every receipt log SHA256 and reproduce the
runner's exact-count, success-banner, exit, skip/fail and startup guards.

Artifact 11539453667 contained only 12 receipt/log entries, no test profiles or
executable payloads. The actual downloaded ZIP was 14342 bytes and SHA256
`ae3d4be3ccbe0409546e650170aebc4a9b902b98b7c6e197a09d1fee02873669`,
matching both GitHub's API digest and upload log. `receipt.json` here preserves
the artifact's exact original bytes; scoped Git attributes preserve its Windows
line endings and the raw Flutter logs' recorded trailing spaces.
`consumer-verification.json` records the
additional local archive/raw-log verification. Decoded full job logs and archive
bytes remain in the consumer recovery directory; their raw transfer references
and diagnostic URL text are deliberately excluded from this repository evidence.

The runner measured these four nonempty required debug files identically in all
six scopes; the fifth required file, kernel_blob.bin, varies per entrypoint below.
These are runner-measured payload hashes. The consumer verified receipt bytes,
not executable bytes, because payload binaries are not uploaded.

| Required debug file | Bytes | SHA256 |
| --- | ---: | --- |
| tandemlog.exe | 1067008 | e6231586dd39e34756c079f578d3ae7a74972ff775fcaa100bcb6a66d0224432 |
| tandemlog_text.dll | 1160192 | e7f619e8fd3abd5f6f5dcca1d4d717c61f250b1f140c290bb66a00c873fea63b |
| flutter_windows.dll | 46623744 | f406dc7b0ddb5b8e3028b79980e560a481bcd02490cc513b495f2d91db29eb25 |
| data/icudtl.dat | 864880 | 325a86063d26334c2eabe1743cea073b612540fbf3d8fc2ef0b5708e3763a8c7 |

| data/flutter_assets/kernel_blob.bin scope | Bytes | SHA256 |
| --- | ---: | --- |
| Checklist workflow | 62661112 | 0186e7f83af74c305a55a6510c40bfb6776f6d028ea7874f473bc3ac890989ff |
| Checklist lifecycle | 62661112 | 69a4b6d9e613f864aadb294bac141f8ce4c55e9cda2896eb9f3d6bca6b14af7f |
| Inbox | 62661088 | 07f6614cd23d79e6a7e2f3cfa05323f3341ec5cbe6d4446cc8ed2fee3088b2b4 |
| Bulk apply semantics | 62661112 | f50131370366457053cf229bef7db512e547ec05fef741d938a6195fb652ae4c |
| Field layout | 62661096 | 63308308445763305426ce81793067e26e94cb669f73f3ff606b1b2fef18febd |
| Exact workspace-search filter | 62661088 | a71e0605940321c0654744b645155cbe0913047e2fcecbaabdd21e2a2a0705ee |

`TANDEMLOG_TEXT_LIBRARY` was unset. The source-declared native loader selects
the adjacent debug-bundle DLL; no runtime loaded-module enumeration was performed.
This result establishes the scoped native Windows debug test workflows. Installed
release-artifact execution, manual visual/accessibility review and native assistive
technology, and Android SAF/IME acceptance remain separate pending gates. No
publication, live synced user data or application changes accompanied this result.
