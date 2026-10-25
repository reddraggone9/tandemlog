# Count-only UTF-8 size guard allocation

Implementation checkpoint: 2026-10-25. This is authorized performance repair
against e23 product source, separate from the parent's immutable Farnsworth e23
measurements. No format, validation, durability, budget or feature change.

## Exact predicate and caller compatibility

Five size checks previously allocated `utf8.encode(value)` solely to compare its
length. The shared domain helper accepts a string immediately only when its
UTF-16 code-unit count is at most `maximumBytes ~/ 3`, for a nonnegative limit.
Each code unit requires at most three UTF-8 bytes, including replacement for an
unpaired surrogate; a valid surrogate pair requires four bytes for two units.
All other inputs retain the original conversion and comparison. Negative limits
also retain that original path. Division avoids a multiplied-length overflow.

The implementation deliberately omits the historical scratch prototype's new
lower-bound rejection shortcut. The pre-existing `LogEvent` raw-length rejection
is unchanged. Canonical scalar validation, JSON decoding, identity checks,
canonical encoding, hashes and error handling all remain in their original order.
This predicate does not validate Unicode or replace any of those checks.

The only integrations are CurrentOperation and LogEvent decoding (1 MiB),
FoodRecord construction (256 KiB), and UnifiedRecord construction/decoding
(16 MiB). Required UTF-8 encodings used for actual hashes remain unchanged.
Queue ordering, transactions, admission, peer-change/tail cleanup, native
ownership and rejected-Save continued typing are untouched.

Before changing product code, two new caller regressions ran successfully on
e23. Their frozen baseline records fifteen caller errors/classes/messages and
valid Unicode Food/action/operation bytes. A separate Python canonical/SHA
fixture matches the named Unicode v5 action. Existing persons/Food fixture
hashes are also pinned; accepted fixture bytes were never regenerated after
integration. The first baseline command had a test-only asynchronous file-read
mistake; it was corrected before product changes and the original failed log
is retained. Existing oversize-before-provider-write tests remain passing.

The actual-helper [functional oracle](utf8-size-guards-integrated-oracle.json)
passes 326,708 comparisons, 30,000 random strings, every Unicode scalar,
malformed UTF-16 and exact format/one-third boundaries. Its archived
[source](utf8-size-guards-integrated-oracle.dart.txt) imports the actual helper;
it is distinct from the preserved historical three-branch prototype.
Three new repository tests add full-scalar, randomized and large-boundary
coverage against the original `utf8.encode` byte count.

## Component observation

The [same-binary AOT component probe](utf8-size-guards-component.json) loads and
parses public synthetic fixture strings before timing. Each case alternates
original/candidate order for two warmups and five measured rounds. Both
predicates have the same non-inlining annotation and return matching checksums.
All original samples, including warmups, remain in the receipt. Times below are
median milliseconds per repeated batch, not per application action.

| Input case | Strings | Calls per batch | Original | Candidate |
| --- | ---: | ---: | ---: | ---: |
| Public outer records | 6,615 | 211,680 | 647.437 | 1.742 |
| Public Task effects | 4,311 | 137,952 | 221.873 | 0.986 |
| Public Food effects | 2,307 | 73,824 | 166.655 | 0.522 |
| Larger-string fallback control | 4 | 16 | 40.873 | 40.082 |

These finite batch observations confirm that the count-only small-string path
avoids encoding work. They do not measure a full action, allocation service time,
UI presentation, or a percentage improvement in startup. The fallback control
still encodes the same strings; its small timing difference establishes no
improvement. The previous cold CPU profile's UTF-8 leaf fraction includes
required encodings and cannot be used to predict this change's overall benefit.
[Probe source](utf8-size-guards-component-probe.dart.txt), source/helper/binary/SDK
and public canonical-file hashes are retained. The first compile command placed
`--packages` on the wrong CLI subcommand and exited before compilation/timing;
that failure is recorded separately from the corrected successful compilation.

## Validation and open gates

[Validation receipt](utf8-size-guards-validation.json): 38 focused tests and all
1,515 full unit tests pass, analysis has no issues, formatting changes none of
399 files, and all 171 tooling tests pass. Initial analysis found two lints in
an already-published scratch evidence source; its exact original bytes are now
archived with `.dart.txt`, links corrected, and analyzer rules unchanged.

The [full source-sealed, uninstrumented application/storage AOT run](utf8-size-guards-full-aot.json)
completed all three shapes, all 232 metrics, first-use/replay/prefix checks and
both paired-growth comparisons. All 118 source pins matched, zero rewrites/shims,
zero retries. Four absolute failures remain, all maximum-only startup misses:

| Shape | Metric | Maximum ms | Bound ms |
| --- | --- | ---: | ---: |
| Base | Warm cache restore | 27.980 | 25 |
| Base | Cold total | 940.157 | 935 |
| Base | Cold history | 897.509 | 890 |
| Task growth | Warm cache restore | 42.192 | 40 |

All median limits and both paired comparisons pass in this local run. Food
growth passes every absolute limit. Cloud resource limits differ from the
enforcing job (16 GiB/four CPU/unbounded swap rather than 6 GiB/two CPU/no swap),
so this is measure-only, `releaseGateAccepted=false`. No selected sample is
repeated and no limit is loosened. This is not a controlled before/after action
comparison; no whole-action speedup is claimed. Fresh exact-source CI remains
required after committing this tested source; the old e23 enforcing failure
remains separately preserved. The run completed within its original 1,500-second
outer bound and each owned child is confirmed absent.

Hosted e23's 28 absolute and three paired failures, the supplied Farnsworth
paired miss, the historical intermittent Linux close SIGSEGV, pending Android
helper validation and Windows hardware input-to-presentation acceptance remain
qualified as documented in the handoff. This patch does not establish their
cause or clear them. No release or live operation is authorized here.


## Exact-source CI checkpoint

[CI 40164354926](https://github.com/reddraggone9/tandemlog/actions/runs/40164354926)
tests pushed product 6e400f7 with calibration disabled. Hosted Linux 1,515 unit
tests, analysis/format/tooling/build/native-payload checks pass. Android job
passes; the cloud independently verifies its archive/APK checksums but performs
no installation. Windows unit step passes; later Windows/performance work is
still active at this snapshot. Linux normal close failed with SIGSEGV. Its actual
sanitized [stack](utf8-size-guards-linux-close-stack.txt) and
[pinned receipt](utf8-size-guards-linux-close.json) locate LLVM/Gallium graphics
compilation concurrent with process exit handlers; this is a disposal-order lead,
not a proven upstream root cause. Warm startup/downstream native workflows were
not executed. No source workaround or CI retry is applied. Fresh required gates
therefore remain incomplete/failed despite byte-equivalence/local checks.
