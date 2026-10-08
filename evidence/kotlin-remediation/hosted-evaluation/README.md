# Kotlin remediation hosted evidence

Both full CI runs passed: first source `ac20d4e0edbcb81d4d80b69b7957fe5243989095`, run 37753131078; follow-up source `45eb9e83fda816cc4c17600821ee9d764ea95e7d`, run 37755702541. Later evidence-only HEADs describe these payloads; they are not new compiled artifacts.

Raw cold/warm JSONL/build/gate/hash files preserve bytes from the verified GitHub evidence ZIP. Local inspection receipts check actual delivered APK bytes against archive/API and hosted manifests. [Review](review.md) distinguishes 11 observed binary tuples from 23 reviewed allowed entries, records source/run/phase/root identities and Android/JVM task classes, and qualifies static packaged APK checks separately from Android runtime acceptance.

Run `sha256sum -c SHA256SUMS` in this directory. The manifest covers retained files other than itself. Large ZIPs and APKs stay outside Git; no temporary resolved references or signing credentials are retained here.
