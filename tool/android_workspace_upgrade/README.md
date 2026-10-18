# Separate Android workspace upgrade QA

This test-only entrypoint is never imported by production. The dispatch-only
workflow builds a separately identified debug APK from reviewed main source,
using the existing pinned Flutter/Java/Rust/NDK setup and Gradle repository policy.
It adds no dependency, permission, native method or owner-signing access. It is
separate from signed candidates and their closed three-installer publication set.

Choose a **new empty synthetic SAF folder** and confirm that choice. A populated
folder is rejected before any fixture creation. Each run creates a new private
SQLite profile and writer, then uses production Task/Food commands and native
text support to create legitimate v3 history. It does not open or copy normal
profiles, inventories or production workspaces. The original selected tree grant
is the only folder access used.

The harness starts a real app-owned upgrade, records its own consent and actual
input/output acknowledgements. At staging and activation, a wrapper first checks
the production SQLite journal for the exact expected/full desired replacement.
It then asks the real AndroidLogFolder/MainActivity checked replacement to write
and confirm a proper prefix, and throws one typed uncertain-outcome error.
It retains the prefix bytes privately, closes/reopens SQLite, reopens the core
upgrade and verifies recovery to the exact journaled full desired bytes.
Original source/backup bytes, sealed converted outputs, full Task/Food views,
native text field state, settings and writer identity must survive without extra
canonical writes. Handles close independently and all evidence is retained.

This is **controlled interruption after real provider writes**, not a claim of
provider-origin partial I/O failure, universal SAF behavior, Android process kill
or power failure. A cold SQLite reopen is precisely the implemented restart
boundary. Exact signed owner APK everyday UI acceptance remains a separate gate.
The workflow compiles the actual production MainActivity and CheckedReplacement;
a successful build alone is not native runtime acceptance.

The UI displays step names and redacts folder URI/history/writer identifiers.
It saves report.json and both interrupted manifest prefixes in the private run
directory; its path is shown for deliberate adb export. The explicit Copy private
synthetic report JSON button exports the complete synthetic report to clipboard.
Only result, source and private report path are logged as
TANDEMLOG_UPGRADE_QA_RESULT. Keep detailed reports/profile/media private.

Native execution, independent review and workflow dispatch are pending. Do not
install this debug APK over a normal Tandemlog installation: its expected package
is com.reddraggone9.tandemlog.upgradeqa and label TEST ONLY Workspace Upgrade QA.
