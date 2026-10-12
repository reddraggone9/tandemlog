# Accepted stable2026.10.4/build71 candidate

Exact source `b8cdfc3941cf171fb6e89bbd19c24e33729799bc`, signed candidate38299989871 and push CI38299988681 passed every required hosted gate. [Acceptance](acceptance.json) binds the original three installers, native upgrades and qualifications. Publication remains pending. No artifacts are rebuilt or relabeled from an RC.

Lee accepted RC3 and authorized its full stable release with audited PR8/PR9. After the disclosed Gradle TLS-fallback blocker he authorized the bounded mitigation. [Build-security review](../build-security/README.md) keeps the original toolchain pins and records29 controlled cases plus independent review.

Native Android acceptance uses only synthetic provider/app-owned fixtures: prepared stable2026.10.3+56→71 and separate RC70→71. Existing histories, Tasks and Food are preserved. Offline native text replay, Food Undo, module isolation and SAF switching pass. Actual runtime is Android11/API30. Some earlier handoffs used an unsupported API36 emulator label; this is an explicit qualification, not a rewrite of their original receipts. SDK/target36 does not prove API36 runtime. Current source-bound Windows/Linux hosted installed lifecycles pass. The applicable manual Windows GUI waiver and inherited Flutter/SQLite RELRO/16KB qualification remain. Earlier unchanged Food/provider/storage proof retains its exact original source attribution.

Both lab datasets are preserved; device settings/adbd privilege restored and transient units stopped under6GiB/2CPU/zero swap. Private snapshots, Food inventory/import rehearsal and Library packet remain outside GitHub. There is no live import, profile change or Food cutover.
