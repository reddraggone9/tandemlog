# Publication inventory correction

This isolated branch changes publication policy and tests, not application,
dependency, native, packaging producer or workflow inputs. The running signed
candidate remains source `77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`, run
37819214432. No candidate bytes were replaced, no rebuild or publication was
performed, and this policy has not been integrated into main.

At source77 the Windows producer stores six files in its artifact: the required
setup installer, checksum and lifecycle report plus portable QA archive,
checksum and member-hash provenance. Completed hosted job113455677076 reports
six uploaded files, artifact11568777570. Publication merges that complete artifact
with Linux and owner-signed Android, producing fourteen files. The original
`publish_gate.py` insists on exactly eleven, so it rejects valid retained QA
before the accepted-APK and installed-desktop gates. Independent architecture
review confirmed this producer/consumer mismatch.

Baseline `ee7d9cbf94b9ad13b9ea5f10100e2eeac5428dbe` extracts the existing eleven-file
check unchanged into a callable function. Its nine tests record seven passing
cases, one valid-QA-set rejection error and one directory-not-rejected failure.
The earlier8353 initial missing-function import red is retained separately and
is not claimed as the behavioral reproduction.

The correction still requires every original eleven file, rejects unknown or
partial optional sets, symlinks/directories and the existing per-file size bound.
The optional QA set is exactly the three producer filenames. Its source SHA,
archive checksum/provenance and every member hash must agree; required runtime
members, unique case-insensitive paths, safe regular files and total uncompressed
size are checked without executing or extracting archive contents. Run authority
continues to come from the validated signed-candidate run and run-pinned download;
manifest run-ID syntax is not a separate authentication claim.

All original accepted APK/hash/signer/version/tag/monotonic-code, desktop lifecycle
and checksum gates remain. Public staging still copies exactly three versioned
installers. Portable QA stays engineering-side in the original candidate artifact;
GitHub automatic source archives are unchanged. Source candidate77 and its already
built package bytes can be consumed by a later reviewed trusted dispatch policy
after exact native acceptance, without rebuilding. This branch's independent review does not authorize publication
or final package/device acceptance.

Thirteen focused inventory tests pass, including the actual unchanged portable
producer, old eleven-file compatibility, three-installer byte-preserving public
staging, malformed/partial/unknown/source/hash/member/path/symlink rejection.
All fifty tool tests pass with no skips after loading the existing pinned
toolchain and resolving the unchanged lockfile offline. The earlier shell without
Dart had one resolver-only compile-test skip, retained and explicitly superseded;
it was not an FFI test. No application suites were repeated for this policy-only
change. Consumer materialization of the actual Windows artifact returned403;
synthetic producer tests and completed runner output are qualified separately
from actual archive-byte/native acceptance.
