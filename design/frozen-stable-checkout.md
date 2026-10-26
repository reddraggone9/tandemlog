# Frozen stable-v3 checkout bytes (2026-10-26)

CI40403722043 Windows failed the unchanged frozen-replay test before replay:
`event.dart` provenance expected `16de7d402144fe86d5a6ea5e258cd071d526bada650303008a7e7632f636b498`,
but the checkout contained `f32692bbd10bb5d277667e625970f9404c0d38ccf689220bf292121b5613a517`.
The latter is exactly the SHA256 of the original LF source converted to CRLF.
The original provenance/golden is correct; Git checkout conversion is wrong.

Before changing attributes, reproduced the identical test/line/hash failure in
the RC checkout using Flutter3.47.5/Dart3.13.4 and only a CRLF-transformed copy of
the sealed event source. Restored that file directly from HEAD afterward.
A separate Git checkout with core.autocrlf=true reproduced the bad hash for all
six sealed reader sources. The new scoped -text attribute preserves all six
original hashes under the same checkout setting. The unchanged frozen-replay
Flutter test then passed. No accepted source, fixture, provenance, assertion or
application behavior was changed; no Windows native runtime test is claimed.

The fix changes .gitattributes, which is included in the conservative reference
source identity. The existing enforcing PASS is retained unchanged but cannot
qualify this successor identity. Per the task stop condition, no new enforcing
qualification, calibration, CI dispatch or release may be inferred from this fix.
