# Stable2026.10.2 official release

Exact stable candidate source is`687163b1f9c95fe8dee1dffa0775ee7fe4cd3884`.
[Signed candidate37960853538](https://github.com/reddraggone9/tandemlog/actions/runs/37960853538)
and [pushCI37960786048](https://github.com/reddraggone9/tandemlog/actions/runs/37960786048)
both completed successfully at that source. [Independent source preparation](independent-source-preparation-review.json)
and [full-range editorial review](independent-editorial-review.json) accept code
equivalence, stable policy/gates and actual notes/README/immutable tag media,
with no must-fix findings. [Bounded new-artifact native handoff](native-acceptance-handoff.md)
defines required identity/upgrade/retained-data checks and reuse limits.

Lee explicitly accepted released RC7 as the next official release on2026-10-09:
“That build seems fine to me. Let's publish it as the next official release!”
This supplies behavior-changing stable acceptance. The parent supplied fresh
publication-threshold clearance at2026-10-09T16:34:51.726011Z; account values are
retained privately.

Established ADR0008/stable.yml/candidate_source/publish_gate require a stable-name
candidate whose source, embedded APK metadata and tag agree, with a higher build
number. Exact RC7 bytes cannot be relabeled as stable. Version2026.10.2/build53
therefore rebuilds metadata only from accepted RC7 source
`74afbe294065f462b742b4570d4095e690e54b04`/build52. Application source, native
vendor/provenance, platforms, dependencies, workflows, tests and durable fixtures
remain unchanged; [code-equivalence record](code-equivalence.json) binds the
actual tracked source inventory. The stable promotion then consumes exact new
stable artifacts without rebuilding again.

Reuse RC7's647 Linux application tests,87 native flows, platform/native payload/
installer-lifecycle evidence, independent implementation/editorial/publication
reviews and parent's56-check exact signed Android acceptance with explicit RC7
source attribution. Those do not identify the new stable APK. The mandatory full
signed-candidate matrix remains intact. Exact stable package/version/code/signer/
ABI/hash, upgrade/retained data/cold replay/SAF continuity and loaded workflow
smokes remain required; broader unchanged feature matrices may be reused.
Use only isolated synthetic profiles/folders and preserve prior evidence/data.

Stable notes cover changes since stable2026.10.1 source
`da4859ea82f8b066ed701740c57cb9bcff1083ff`, rather than only the last RC delta.
The existing tag Before/After image retains its immutable source and accurate
earlier-preview capture attribution in rc4-editorial/media-receipt.json. Prose
describes the other meaningful changes; no new app pixels or comparisons are
invented. Separate editorial review must assess the full stable range and actual
notes/media/README before publication.

The full signed candidate passed all platform checks, including647 Linux
application tests,87 native flows,107 contracts and50 policies. Windows passed
645 application tests with two documented Linux-only skips; new-version release
payload, startup and installer lifecycle checks passed on both desktops.
Signed Android job113932239992 verified the pinned owner certificate, stable
name/build53, package, non-debuggable flag, all three ABIs and exact native
payload/notices before upload. The signed artifact is11632728225, ZIP30362267B,
reported SHA256`8a6b43e6edaa05e13447226d0a6136210c871ccc833addc8de6acd7a4bb749f7`.
This archive digest is not the inner APK hash. Current supported cloud archive
materialization returnedHTTP403. Parent subsequently verified the actual archive
and accepted36 bounded native checks, reusing56 unchanged RC7 behavioral checks,
against inner APK SHA256
`b825c02c7214109a87d70643fa83985c1d9101d112fb9f593e19991119ae8ecd`.
[Native acceptance attestation](native-acceptance-attestation.json) records
identity/upgrade, all four retained synthetic profiles, cold replay and SAF
continuity. Settings/lab were restored/stopped, with no new OOM events or live
synced user data operation. Packet byte/device checks belong to the parent.
Fresh parent publication clearance at17:25:54.451529Z passed; account values
remain private. No RC7 APK identity is substituted.

## Published result

[Official release](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.2)
408169620 published2026-10-09T17:31:53Z, prerelease=false/draft=false and Latest.
Successful [promotion37966878729](https://github.com/reddraggone9/tandemlog/actions/runs/37966878729)
at trusted dispatch13d3ce412ad729fb4ac5da00cc0e149138706812 consumed exact
candidate687163b artifacts without rebuild. Actual downloaded archive digests,
closed inventory, portable full-member/CRC/provenance, both desktop installed
lifecycle records, accepted APK identity and three strict installer checksums
passed before release creation. [Hosted excerpt](promotion-hosted-byte-gates.log)
retains actual terminal output, with full-log hash in the public receipt.

Root anonymously downloaded all three actual public installers and verified
size/SHA256 against GitHub, Windows producer hash and accepted APK hash.
Official SDK apksigner/aapt verify owner/package/stable53/nondebuggable/three ABIs;
all79 APK members pass CRC, exact native payload/notices pass, and all three
native libraries are byte-identical to accepted RC7. Stable tag resolves to
687163b, reviewed notes are byte-identical to immutable dispatch, and all20
prior releases' notes/metadata/asset identities remain unchanged.
[Public verification](public-download-verification.json),
[prepublication review](independent-prepublication-review.json) and
[independent final review](independent-post-publication-review.json) bind actual
bytes, review decisions and runtime origins. Native device evidence remains
parent-attributed; hosted lifecycle evidence remains hosted-attributed.

Earlier candidate-handoff and preparation receipts are preserved checkpoint
snapshots, including their then-pending native/publication gates. No live synced
user data was changed; private Library identifiers/account values are omitted.
