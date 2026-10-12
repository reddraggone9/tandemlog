# Stable build-security qualification

Lee explicitly approved a bounded mitigation before signing on2026-10-12.
Application code and Gradle9.4.1/AGP9.2.1/Kotlin2.4.20/Flutter pins remain unchanged.
The official TLS-fallback workaround is implemented with disjoint content filters
in every settings/plugin/project/buildscript repository handler, including nested
builds and future repository additions. Each module can resolve from one approved
logical repository only; HTTPS errors cannot expose the same coordinate at a
different repository. Unknown types/endpoints, secondary artifact URLs, later URL
changes and content widening fail closed. This is repository routing, not a new
claim of cryptographic verification of all Maven artifacts.

The policy is installed in a fresh job-temporary Gradle home before Android
resolution and byte-verified before materializing the owner keystore. It has no
external init-script classpath. The supported wrapper ABI is explicitly9.4.1.
Exact Gradle source confirms plugin wrappers copy their delegate's content
descriptor; the policy accepts only wrappers whose delegate is already guarded.

The v4 matrix passes21 cases: two positive controls, two unprotected plugin
fallback controls and17 protected negatives. Every protected negative has zero
requests to the later repository. The final version-pinned policy passes the
four v5 affected positive/TLS cases with its exact production hash. The v4 core
and v5 core are identical except the added explicit supported-version guard.
Each case uses a new Gradle cache, controlled loopback HTTPS and an isolated
fixture-certificate truststore; no owner credentials or external TLS bypass.
The synthetic plugin prints a harmless sentinel only.

Earlier v1-v3 receipts are preserved: v1's positive fixture had an incorrect POM
group; v2 exposed rejection of Gradle's internal plugin wrapper; v3 exposed
Groovy closure delegation on that wrapper. They are test/policy setup failures,
not production app failures. v2 plugin negatives were false positives and are
superseded by v4's successful positive plus real TLS-failure negatives.

Gradle's two local daemon advisories remain mitigated by trusted single-tenant
ephemeral build hosts. This policy does not repair those protocols. Owner signing
must not run on shared hosts. An eventual patched Gradle upgrade requires a
separate full dependency/compatibility audit; it is not silently included here.

Full CI, original signed-candidate artifacts and exact native stable upgrade
acceptance remain pending at this preparation checkpoint. No private Food
inventory or native evidence packet is included in these synthetic receipts.

Sources:
- https://github.com/gradle/gradle/security/advisories/GHSA-j5m7-59rp-24f5
- https://github.com/gradle/gradle/security/advisories/GHSA-mvvg-497x-hmj8
- https://github.com/gradle/gradle/security/advisories/GHSA-xwqc-3h47-hg64

## Corrected legacy coordinate ownership

Initial final-source candidate38296861898/push38296862559 failed Android debug
before signing: file_selector_android's existing AGP8.13.1 → grpc-core1.69.1
classpath requires com.google.android:annotations:4.1.1.4 from Central. The
original namespace-only policy incorrectly assigned it to Google. Both runs
were cancelled after preserving the failed Android job receipts; no eligible
owner-signed APK exists from that source.

The corrected policy gives the annotations module one repository owner, Central,
and admits only its audited fixed4.1.1.4 version. Google excludes that module
including dynamic version listings; Central rejects other modules/versions in
the otherwise Google-owned group. The two source files match official
android-4.1.1_r4 bytes exactly. The3120-byte annotation-only JAR has no executable
entry point/service hooks and retains SHAba734e1e84c09d615af6a09d33034b4f0442f8772dec120efb376d86a565ae15.

Exact final-policy v7 passes29 cases: three positives, four unprotected fallback
controls, and22 protected negatives with zero later-repository requests. This
includes fixed and dynamic annotation lookup, later content widening and
unsupported module/version boundaries. v6 and real public Maven resolution
retain their earlier exact-policy attribution; the final one-line hardening
changes Google from an exact-version exclusion to a complete-module exclusion.
No existing dependency version or application source changes in this correction.
Fresh full Android/candidate/native gates are still required.
