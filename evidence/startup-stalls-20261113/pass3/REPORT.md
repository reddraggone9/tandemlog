# Pass 3: background owner for shared-profile SQL

Goal (Lee 11-13): no UI-isolate gap over 16.7 ms (aim 8.3 ms) on strict and warm launch to the first list, and time to first list not slower than origin/main. **Not fully met** (see Remaining). No release, install or live profile was used.

## What changed

- `LocalProfileDatabase.transactionAsync` / `ProfileTransaction.run`: one BEGIN IMMEDIATE...COMMIT whose SQL may run on a background isolate that borrows the same native connection (`sqlite3.fromPointer(borrowed: true)`, bundled SQLite THREADSAFE=1). While lent, every UI-isolate route to the connection throws; any failure (job, UI body, COMMIT on the owner, dead worker) rolls the whole transaction back on the UI isolate after the handle is back; memory publishes only after COMMIT, in the same order as before. `readOffIsolate` does the same for read-only jobs.
- History commit (location, workspace, heads, history-store rows, COMMIT) runs as one owner job; strict opens send it rows serialized by the pre-decode workers. Under 64 records the same job runs inline.
- First Task attach: projection copy from the validator's scratch DB (lent), index DDL and the visible-row decode/freeze run on the owner inside the attach transaction; the synchronous stage uses that work only for the exact branch/snapshot/revision it was prepared for.
- Warm history-store read (rows, byte rebuild, decode) is one read-only owner job.
- Strict opens pre-decode each writer file on its own isolate; the chain walk still checks every record and adopts a decode only for the identical raw line.
- Food admission starts alongside the Task stages; its result/failure is taken at its own stage as before. Validation/decode slices 4 -> 8 ms (longest validator slice seen 9-13 ms).
- Loading screen matches the first list's font variants between frames (Roboto 500 and 700, Material icons; found by walking the first list's render tree: only 400/500/700 and the icon font).

## Measurements

Existing paired harness (`stallrun.sh`, synthetic template), release Linux bundles, five serial interleaved pairs, one strict plus one warm per binary per pair, no tests/builds during runs. Household load was NOT quiet (load average 5-30: media ffprobe/ZFS writes, slskd); both sides interleaved. Raw lines with every gap >= 8 ms: `p3*-{before,after}-N.txt`, all landmarks in `measurements.json`.

| Batch | Mode | Before (origin/main) max gap, median | After max gap, median | Before app->list median | After app->list median |
|---|---|---|---|---|---|
| p3 (97995dfe) | strict | 742-892, 837 ms | 28-45, 36 ms | 2155 ms (2063-2223) | 2174 ms (2115-2207) |
| p3 (97995dfe) | warm | 57-63, 59 ms | 28-37, 31 ms | 356 ms (351-381) | 431 ms (423-452) |
| p3b (48b01b1d) | strict | 772-869, 781 ms | 25-32, 28 ms | 2155 ms (2103-2224) | 2255 ms (1960-2379) |
| p3b (48b01b1d) | warm | 58-73, 62 ms | 30-50, 37 ms | 386 ms (369-425) | 398 ms (379-433) |

48b01b1d is the final source. Its commit-job change removed the 36-45 ms gap just before the strict commit (p3). Elapsed differences are within the noisy-machine spread for strict; warm stayed 12 ms slower at the median in p3b and 75 ms in p3 (before the store-read and commit-copy fixes).

## Remaining (over one frame)

1. Font variant matching: each new weight costs one native Fontconfig call of about 18-25 ms on Bender (the Linux Typography fallback list Roboto, Ubuntu, Cantarell, DejaVu Sans, Liberation Sans, Arial; only Liberation Sans is installed). A single call cannot be split; the warmup turns one 57-74 ms first-list frame into two ~20 ms gaps during loading. Linux-specific; Android/Windows not measured.
2. First-list frame ~25-31 ms of build/layout (fonts no longer in it).
3. Warm open's first synchronous chunk at ~80-110 ms (manifest, folder listing, store probes): 30-50 ms, present on origin/main too (31-48 ms).
4. Startup [0, 22-24] heartbeat gap at Dart entry (also on main).
5. Time to first list: not shown faster than origin/main; strict median +19 / +100 ms and warm +75 / +12 ms across the two batches on a loaded machine. Needs a quiet-window five-pair run before any claim.
6. Phones unmeasured (no install allowed).

## Verification

- `flutter analyze`: no issues. Full suite: 1,938 passed (48b01b1d). New: `test/profile_owner_transaction_test.dart` (10: THREADSAFE build, fence while lent, job failure rollback, UI failure after job, body failing before its job ends, COMMIT failure on the owner, stopped-process copy shows no partial rows, lent scratch DB, publish-after-COMMIT order and failing stage publishes/attaches nothing, strict+warm rows/view/branch counts and full DB dump identical to the synchronous path), `test/text_style_warmup_test.dart` (2).
- Linux release bundle built from 48b01b1d (`bundle-pass3b`).
