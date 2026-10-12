# Android build dependency repository routing

Status: accepted bounded build-security mitigation,2026-10-12; final release gates pending.

Context: Gradle9.4.1 can continue to a later repository after some SSL failures.
The signed build resolves dependencies while owner signing credentials are
present. Fresh single-tenant runners mitigate separate local daemon attacks,
but do not address repository fallback. Lee approved auditing and validating a
bounded fix before signing.

Decision: keep the existing toolchain pins and enforce strict disjoint group
routing on all Gradle repository handlers before resolution. Google owns Android
and AndroidX groups, the Portal owns Gradle Kotlin DSL plugin groups, Flutter's
repository owns io.flutter, and Central owns all other groups. Exact HTTPS
endpoints are required; secondary URLs, unknown types and late mutations fail
closed. Complement exclusions prevent later content inclusions from widening
the routing. The policy covers settings plugins, included builds, buildscript
classpath, normal and detached configurations, and dynamically added repositories.
It uses no external init-script dependencies and is explicitly pinned to the
reviewed Gradle9.4.1 internal plugin-wrapper ABI.

CI installs the policy into a fresh job-temporary Gradle home before any Android
Gradle invocation. Owner signing verifies the installed bytes before writing its
temporary keystore. Existing signing admission, owner pin, cleanup and exact
artifact publication gates remain required. Local owner builds must install the
same policy first and use a trusted, unshared host.

Alternative: Gradle9.8.1 fixes all three advisories, but also changes embedded
Kotlin and many bundled libraries. The pinned Flutter included build compiles
with Kotlin2.2.20; KGP2.4.20's documented fully supported maximum is Gradle9.7.
That larger toolchain audit and compatibility qualification is deferred. Partial
root-only filters, warning suppression and runner isolation alone were rejected.

Consequences: resolution fails when a dependency is absent from its assigned
repository; investigate provenance instead of adding a fallback. This is not
checksum verification or a claim that an approved repository cannot be
compromised. The local-daemon workaround still requires trusted ephemeral hosts.

Debt owner: release maintainer. Exit: replace the vulnerable Gradle runtime after
an audited compatible patched version passes release compilation and native
runtime. Revisit at the next toolchain upgrade or changed repository/group graph.
Any such change must requalify this policy and its pinned internal ABI.

[Synthetic qualification](../../evidence/stable-2026.10.4/build-security/README.md)
records the controlled TLS regression, positive controls and retained setup failures.
