# Proposed next bounded repair — UTF8 size checks

**Proposed only. No product/test implementation, performance run or gate change
has been made.** Product stays at exact e23. The first next step is a scratch
differential oracle and caller-compatibility review before a substantive patch.

The existing [cold CPU profile](followup-cold-start-cpu-profile.json) reports
UTF8 encoding at about6% of sampled leaf CPU, alongside canonical encoding,
hashing and semantic validation. This is not an exclusive wall-time partition;
the profile does not separate required hash encoding from count-only conversions.
It therefore provides a concrete investigation target, not a promised6% gain.

Five current size predicates allocate UTF8 bytes only to obtain their length:

- `CurrentOperation.decode`:1MiB.
- `LogEvent.decode`:1MiB, already with a code-unit lower-bound rejection.
- `FoodRecord` construction:256KiB.
- `UnifiedRecord` construction and decoding:16MiB each.

The reviewed pinned Dart3.13.4 `Utf8Encoder.convert` implementation allocates
encoding storage and encodes unpaired surrogates as replacement characters. A
UTF16 code unit produces at most3 UTF8 bytes; a valid surrogate pair produces4
bytes from2 units. Encoded byte count is also never below code-unit count.
Therefore the proposed count-only predicate is:

```dart
if (value.length > maximumBytes) return true;
if (value.length <= maximumBytes ~/ 3) return false;
return utf8.encode(value).length > maximumBytes;
```

This retains exact UTF8 counting in the ambiguous band and changes no limit.
It is not scalar validation: the existing canonical/JSON/hash/native validators
must still run unchanged, including rejection of invalid Unicode where required.
Using division avoids an unnecessary multiplied-length calculation.

[Read-only cloud fixture inspection](utf8-size-guard-static-review.json) found all
6615 physical envelope strings within the16MiB conservative bound, all6618 data
effect strings within the1MiB bound, and all2307 Food effect strings within the
256KiB bound. These are existing public cloud fixture copies, not Farnsworth raw
artifacts. They show broad eligibility of these strings, not runtime call counts,
constructor execution or measured performance improvement.

Before a product patch:

1. Differentially compare against the original `utf8.encode(value).length`
   predicate for ASCII,2/3-byte characters, supplementary scalars and malformed
   UTF16, including empty strings and boundaries around256KiB/1MiB/16MiB and
   the one-third fast-path boundary.
2. Audit all five callers for unchanged ordering and failure classes/messages;
   retain frozen current/legacy canonical bytes, hashes and oversize rejection.
   Reject the proposal if its proof or caller parity fails.
3. Only then present a minimal helper/five-predicate patch for the next scoped
   implementation step. No cache, native ABI/SHA feature, persistence/format,
   durability, queue, peer/tail, admission or budget change is proposed.

No additional Farnsworth or hosted performance attempt belongs to this completed
comparison. Any later timing validation requires a separately scoped changed-source
step; current failed evidence and hardware/UI qualifications remain intact.
