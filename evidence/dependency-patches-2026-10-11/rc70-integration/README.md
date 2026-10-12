# PR8 integration with published RC70

The dependency proposal integrates main b9474a575bba7bae70ed55eac7f8d80020ca8859, retaining the accepted RC70 editor fixes and separately reviewed release notes. No merge conflicts occurred. All 214 application/native/platform/packaging files compared equal main, and every workflow equals main except the audited immutable upload/download pins and the upload version annotation. Signing permissions, cleanup and trusted-main admission remain unchanged. The audited pub lock and three smoke fixtures retain exact bytes.

Prior PR8 source 54e4ac0011710648d670c7e9c801f058e79256fe passed all three jobs in CI38170327228. That historical pass is not relabeled as current-head acceptance. The unchanged cross-run artifact and Linux native folder smokes retain their original attribution; no new signed candidate, install or Android/Windows GUI claim is made.

Local release/tool suite:79 tests ran,78 passed and one existing platform skip. The initial unprivileged transient-unit launch stopped before tests because sudo required a password; the normal authorized root route then ran the tests as nibbler under6GiB/two CPUs/zero swap. Both receipts are preserved. Synthetic hashes printed by a package test are fixture values, not installer identities. Raw main-owned evidence logs retain their original whitespace.

The existing npm advisory and GTK capability/dispatch limitations remain documented; no new security or product implication was identified in this unchanged dependency patch. No temporary smoke workflow, held AGP/Gradle update, workflow admission relaxation or signing change is integrated. No personal Food data is used. Current main includes preview Food behavior and is not authorized for a dependency-only stable release.

Keep PR8 draft and unmerged until required current-head full CI and coordinator review complete. This preparation updates only the proposal branch and records readiness; it does not merge or publish.
