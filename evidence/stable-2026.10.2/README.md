# Stable2026.10.2 preparation

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

Remaining: reviewed preparation, successful stable signed candidate, exact bounded
stable-native acceptance, retained hosted inventory/archive/member/lifecycle/
APK/checksum gates, stable publication with lee_accepted=true/latest=true, all
three actual public installer bytes and independent final release review.
No stable dispatch/tag/release has occurred at this preparation checkpoint.
