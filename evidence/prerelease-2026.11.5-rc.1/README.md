# 2026.11.5-rc.1 / build126

## Scope and compatibility

Weekly-review fixes (11-23) plus Dependabot #21. Agent `purchases plan` suggests
existing products only on a shared name word (singular or plural), closest first,
never on a shared brand alone. Agent `food add-another` without `--expiry` dates
new containers as the app's Add another (today + Keeps for, else none) with blank
retention, instead of copying the source. `task.textEdited` saves normalize Repeat
list separators like other new input, keeping stored rules stable123-readable.
`actions/setup-java` 6.2.0 → 6.3.0 (reviewed, design/dependencies.md). No format
revision or migration; no UI change.

## CI and tooling fixes made during the release

- `checks / linux` failed twice (45199076556, 45199795234): archive.ubuntu.com now
  answers 403 to urllib's default `Python-urllib` User-Agent (reproduced from the
  engineering host; an explicit agent gets 200). 3e991110 sends an explicit
  User-Agent; URLs, sizes and SHA256 pins unchanged. CI 45206809818 all ten PASS.
- The reference controller refused at plan on its exact-kernel guard (7.3.4 vs host
  7.3.5). Reviewed the upstream 7.3.4→7.3.5 patch: MemAvailable, meminfo, vmstat and
  PSI unchanged; ZFS module and arc_os.c unchanged. Kernel-literal-only controller
  `d3a975d2…` registered in c4438feb ([qualification doc](../../design/performance-reference-qualification.md#arc-accounting-kernel-refresh-2026-11-23)).
  CI 45223684619 all ten PASS. Earlier Android CI 45152435517 (Kotlin plugin "not
  found") did not reproduce with a fresh Gradle home and passed unchanged in 45199795234.

## Local correctness

Failing tests first for each finding; local full suite 1953 PASS before the review
fix commit, CI full suites on every final commit; Python tool tests 314 PASS (2 skipped). Independent code review PASS (46662bc8 applied its findings).

## Qualification

Request `52e14803d3340c25a0596e12ebeb68a1` qualified c4438feb once: absolute and both
growth budgets PASS, clean cleanup, owned ADB server idle. Two first-pass misses
(`dense-2:food.product.bulkEdit.undo` 16.4 ms vs 15 ms; its task-own-history growth
pair) cleared on the gate's automatic rerun (10.3 ms). Receipt d11ce1c7; RC124's
retained as `retained-2d9b15fe`. An earlier admission timed out on media seeding I/O
and a stale Gradle daemon (no measurement), and request 13c72dc8 refused at plan on
the kernel guard (no measurement). Native cold start median 560 ms (budget 1000 ms;
samples 560, 580, 580, 550, 550), f5de444d.

## Candidate and exact acceptance

Signed candidate [45228517132](https://github.com/reddraggone9/tandemlog/actions/runs/45228517132)
on f5de444d passed all 12 jobs; candidate verification PASS (signer pin, v2 only,
non-debuggable). Exact APK/Flatpak installed over public stable 2026.11.4/125 (installed
bytes equal to the public asset) in the retained synthetic Android and GTK labs:
canonical files unchanged by install and prefix-only after use, SQLite integrity,
Android install identity and folder grant PASS. Exact Flatpak CLI: brand-only line
gets no suggestion, plural/singular lines match, add-another gives today + 1 week /
no date with blank retention, a title edit with `Monday,  Thursday` stores
`Monday, Thursday`; `verify` PASS. GTK two cold reopens, normal exit 0, app shows the
CLI writes; Android two cold reopens usable. [Receipt](native-acceptance45228517132.json).
Not covered: Windows GUI (Lee's own trial; hosted install/portable gates passed); the
app text editor's textEdited path was exercised through the CLI, store test covers both.

## Published and verified

[2026.11.5-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.5-rc.1)
published 2026-11-23T18:08:12Z, immutable prerelease, not Latest. All four anonymous
downloads match the accepted hashes/sizes; signer/version, source/tag and reviewed notes
PASS. Latest remains 2026.11.4; all 59 prior releases/tags unchanged.
[Public verification](public-verification.json).

## Isolated Android handoff

Background-installed **Tandemlog RC126 test** (`com.reddraggone9.tandemlog.rc126`,
owner-signed, 2026.11.5-rc.1/126) on Lee's phone beside unchanged stable 125.
Packaging-only rebuild of f5de444d (app ID, label, activity name), not the published
APK bytes. Bound folder: private snapshot copy in Documents/Tandemlog-RC126-test;
live data untouched. Binding and first launch wait for Lee's folder picker.
No stable promotion.
