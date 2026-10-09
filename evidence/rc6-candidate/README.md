# RC6 release verification

[Published RC6](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.2-rc.6),
version2026.10.2-rc.6+50, targets exact source
`2aa46be9043251c8ed4e21b2ad00d41aa054dffc`. Successful
[candidate37889870105](https://github.com/reddraggone9/tandemlog/actions/runs/37889870105)
was promoted without rebuilding by
[promotion37896129554](https://github.com/reddraggone9/tandemlog/actions/runs/37896129554).
Release407616987 was published at2026-10-09T06:56:07Z as a non-draft prerelease
with latest=false and exactly three public installers. Stablev2026.10.1 remains
Latest; all18 previous releases are unchanged.

- [Parent/local native acceptance attestation](native-acceptance-attestation.json)
  binds51 signed Android checks and unaffected RC5 coverage to the exact accepted
  APK. The1.395-second stationary-hold/drag/Undo demo and device checks were
  performed by the local worker; this cloud worker did not rerun them.
- [Independent hosted prepublication policy review](independent-hosted-prepublication-gate-review.json)
  records the required gate order. Its remaining field records the pre-dispatch
  checkpoint; the final review below closes that checkpoint.
- [Actual public-download verification](public-download-verification.json)
  records all three installer sizes, SHA256 values and public URLs, plus official
  APK signature/identity, native payload/notices, tag/source, notes and prior
  release preservation checks.
- [Independent post-publication review](independent-post-publication-review.json)
  accepts actual downloaded bytes, APK identity, terminal hosted artifact gates,
  notes/media and release preservation, with no must-fix findings.
- [Earlier candidate-placement review](independent-artifact-review.json)
  preserves the historical HTTP403 limitation. Normal hosted publication verified
  actual candidate archive digests, Windows portable member hashes/CRC, both
  installed-desktop lifecycle reports and installer checksums before creating the
  release. Public installers were then downloaded and checked independently.

The two attestation/policy receipts are public projections omitting private
Library identifiers and personal quota values. Complete originals remain in the
recovery workspace. The native evidence archive SHA is parent-reported; its cloud
materialization was blocked and its local verification is not claimed here.
Original failed build49 evidence and source-attributed debug media remain in
[checklist controls](../checklist-controls/README.md). The reviewed release notes
and media were unchanged by this documentation checkpoint.
