# Production store audit

This standalone CLI opens the **actual app TaskStore and SQLite implementation**, not a second event projector. It needs no Flutter or Dart installation on the target machine. Use it only on an existing, quiescent dry-run canonical folder, with a new private output directory outside that folder.

## Build and package

```sh
dart build cli --target tool/store_audit.dart --output /tmp/tandemlog-store-audit-build
```

Ship the complete resulting bundle, preserving this relative layout:

```text
bin/store_audit
lib/libsqlite3.so
```

A plain `dart compile exe` does **not** include the sqlite3 code asset and is insufficient. The bundle is Linux x64 for this handoff; it uses ordinary system glibc libraries and `/bin/chmod`. It does not require system SQLite because the exact package asset is included. Rebuild for another host platform rather than labeling this binary cross-platform.

```sh
/path/to/bundle/bin/store_audit /private/staged-canonical /private/new-audit-output
```

The output parent must exist; the output itself must not. On Unix the CLI sets the output directory to mode 0700 before writing private task data. Do not reuse an output directory, place it inside canonical data, or publish it. Keep the bundle's `bin` and `lib` relationship intact.

## What passes mean

The transport exposes canonical reads only: `create` and `append` fail. A pre-existing manifest is required. The CLI hashes canonical files, opens a fresh production SQLite cache, captures its materialized rows, closes and reopens the cache, then requires exact row equality and zero canonical-log reads on that unchanged reopen. It checks canonical hashes again. Canonical symbolic-link entries are refused.

Aggregate JSON goes to stdout. Private outputs are:

- `semantic.json`: actual production domain rows, including current order and completion dates; this contains personal data when run on personal input.
- `canonical-hashes.json`: before/after hashes for every top-level canonical file.
- `report.json`: counts and audit results, or failure details.
- `cache/`: disposable production SQLite cache and audit-only local writer identity.

Counts are measured from the supplied staging folder, never hardcoded from an earlier source inventory. Compare the private semantic snapshot independently with the same source revision. This audit does not replace that comparison, test Android SAF, or modify completion state to generate new occurrences.

Failure paths still attempt canonical integrity evidence, including when cache close fails. If output storage itself fails, the CLI preserves the original error but cannot promise a report file. Concurrent external changes produce a failed audit; retry on a quiescent staging folder with a fresh output directory. Future-clock warnings remain nonblocking, matching the app.

## Validation

The focused tests cover production ingestion/cache reopen, exact canonical preservation, refused output reuse/containment, case-insensitive Windows path guards, denied transport writes, private Unix output permissions, and close-error reporting. Relocation must also be exercised on the compiled bundle: copy only its declared files into a new directory, clear environment variables and run against sanitized canonical data. Inspect native loading to ensure SQLite comes from the relocated `lib` directory, not a build workspace or SDK cache.
