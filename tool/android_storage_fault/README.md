# TEST ONLY Android storage fault APK

This isolated overlay imports the unchanged production storage code from
`76c5dd5cb7eedb09d2d4b62f737d429e1abab7d9` (2026.10.3/build56).
Package `com.reddraggone9.tandemlog.storagefaulttest` uses SDK debug signing,
its own app-private synthetic roots, and the existing fully qualified activity.
It does not change production main, dependencies, owner signing or the candidate.
The separate QA branch's Android build exports immutable production source and
overlays only two target files and the application identity/label. Provenance
binds the source, overlay, lockfile, all patched tracked inputs, APK and every
native payload. Any build-induced tracked input change stops packaging.

Run the delivered artifact on a selected actual Android worker with Python/ADB:

```bash
python3 /path/to/extracted/android-storage-fault/qa-source/run_on_device.py \
  --artifact-directory /path/to/extracted/android-storage-fault \
  --source 76c5dd5cb7eedb09d2d4b62f737d429e1abab7d9 \
  --serial emulator-5554 \
  --output /path/to/new/android-storage-fault-evidence
```

The runner verifies APK/native hashes and actual runtime API/ABI, installs only
the fixed QA package, and creates a fresh retained case for each of eleven cuts.
For each case it first holds a committed legacy WAL, verifies the marker belongs
to the live PID, force-stops this package and confirms exit. It then launches
migration, waits for the exact boundary's durable marker and held DB, force-stops
that exact QA process, confirms exit, and relaunches the same root for recovery.
Reports must match the source/root/marker/current PID and be written after profile
close. They assert preserved writer/settings, guard acknowledged head and pending
reservation, exact private intent bytes, canonical hashes, accepted cache events,
trusted stream/range observations, complete cleanup and retained unknown files.
The first case also injects real SQLite capacity failure and requires result13,
rollback and exact pending evidence. No package data reset, sidecar deletion,
live-profile access or owner-package force-stop occurs. Retain all JSON/logcat.
Use `--cut activation.committed` for a bounded first smoke; repeat `--cut` to select
several cuts. Omit it to run all eleven.

Manual control is `app_flutter/storage-fault-control.json` inside the QA package:
`{"case":"fresh-safe-id","mode":"cut","cut":"activation.committed"}`.
Allowed modes are `seed-held`, `cut`, `resume`, `sql-full`; arbitrary roots, unsafe
case names, unknown keys and unsupported cuts are rejected. `seed-held` leaves
`ready.json` at boundary `legacy-wal`. After external termination, `cut` can use
that same seed, or `resume` can directly verify legacy WAL import. Each migration
cut needs a fresh case; a retained cut marker is never replaced by another cut.
The worker must compare source, boundary and live PID before killing and must
prove PID exit; an old marker/report or an orderly reopen is not death evidence.

Limits: this is QA storage/process evidence, not the exact owner-signed installed
production app, SAF/provider behavior or physical power failure. Marker writes
flush the file; Android directory-barrier guarantees are not claimed. Host tests
use an explicitly synthetic marker and do not claim Android process death.
