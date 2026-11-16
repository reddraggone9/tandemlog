# 2026.11.4-rc.1 / build124

## Scope and compatibility

Five accepted weekly-review findings: retain empty Keeps for editor focus;
manual agent expiration is not estimated; clearing an absent product shelf life
is a no-op; shelf life accepts years as 12 months; Repeat list separators tolerate
missing/extra whitespace. New recurrence commands alone normalize unsupported
separator whitespace to stable123-readable spelling. Historical records and
successor derivation are not normalized. No format revision or migration.

Independent review of b771036 accepted four Food fixes and release-note coverage,
and identified recurrence compatibility as a blocker. Commit9cbc3fd fixes that
at command capture; frozen stable123 parser checks cover created/edited records,
completion successors and exact historical bytes. Independent read-only recheck of9cbc3fd PASS: no remaining compatibility blocker; frozen parser matches stable123 except its import.

## Local correctness and UX

Initial failing regressions reproduced all five accepted findings before fixes.
Initial full suite1948PASS; affected suite133PASS. Compatibility affected suite
55PASS; successor assertions2PASS. Targeted analysis and diff checks clean.
Final full suite1950PASS (`flutter test --reporter compact`, exit0). Final native recurring workflow1PASS; executor cleanup
exit unknown after the test reported success. Prior native shelf-life suite28PASS
and separate Repeat workflow1PASS. Native dark Food capture reviewed independently:
cleared field remains visible/focused and product name remains Strawberries.
No new screen/layout introduced. Narrow/light/large-text review was not supplied.
Release notes independently accepted for exact feature diff; no explanatory media
required by reviewer. Windows GUI remains Lee's own trial, not automated coverage.

## Architecture review

The fixes stay within existing Food product/editor and agent command boundaries.
New-input separator normalization is centralized at TaskStore command capture and
copies caller maps; decoding, replay, canonical history and successor semantics
remain unchanged. No new dependency, persistence format or migration is introduced.
The frozen parser is test-only compatibility evidence, not production duplication.

## Qualification, candidate and delivery

Final development CI [43838620223](https://github.com/reddraggone9/tandemlog/actions/runs/43838620223) passed all ten jobs on3bebd80. Original43835149642 passed nine jobs but failed Windows because the new regression test deleted its temp directory before asynchronous TaskStore.close completed. Test-only3bebd80 awaits closure; local targeted2PASS and hosted Windows unit suitePASS. No unchanged rerun.

Final controlled-reference request `2d9b15fe79a9e9584945030648745883` qualified3bebd80 once; absolute and both growth budgetsPASS, original executor/finalizer exit0, verified work-complete boundary and all owned processes absent. Receipt committed66a9532, identity `fb903dc5505132fda84a086429cc668586a1e9b8f6467089759ebac306de668d`. Initial prelaunch refusal (retained private) was the stopped lab's remaining adb5054 server, not a measurement; it was stopped before the single admitted invocation. All paused background services and backup timer restored; purpose fence released.

Initial signed candidate43847261578 on66a9532 failed its native cold-start
receipt gate because that receipt was stale for this source. Fresh exact native
cold-start measurement passed at median570ms (budget1000ms, samples560,570,580,570,560),
committed3a9e7d8. No unchanged-source rerun. Corrected candidate
[43853267396](https://github.com/reddraggone9/tandemlog/actions/runs/43853267396)
passed all12 jobs on3a9e7d8fe2f4e60a553dcedcbe518ba29c68abac.

## Exact native acceptance

Accepted the downloaded candidate APK and Flatpak over stable123 in isolated
synthetic Android and GTK labs. All five changed workflows PASS; three valid
weekday-list separator variants save/reopen identically, malformed lists reject,
Keeps for retains focus/name, 1/2years persist as12/24months and clear to null.
Exact Flatpak CLI confirms explicit expiry clears estimated and clearing an absent
product changes nothing and appends no log. Canonical prefixes and manifest,
Android install identity and folder grant, SQLite integrity and Settings audits
PASS. Two cold reopens on each platform; GTK normal exit0 both times.
[Receipt](native-acceptance43853267396.json). Native labs stopped after acceptance.

Coverage limits: no Windows GUI claim (hosted installed lifecycle/portable gates
passed); new-container year-derived expiry was not independently exercised;
installed private SQLite extraction completed after workflows, while package and
grant snapshots preceded them and authoritative before/after snapshots remained.

## Published and verified

[2026.11.4-rc.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.4-rc.1)
published2026-11-16T11:44:55Z, immutable prerelease/notLatest. All four anonymous
public downloads match accepted hashes/sizes; signer/version, source/tag and
reviewed notes PASS. Latest remains2026.11.3; all57 prior releases/tags unchanged.
[Public verification](public-verification.json). Initial staging failed on GitHub
HTTP502 before draft creation; retry created one verified draft, then published it.

## Isolated Android handoff

Background-installed **Tandemlog RC124 test**, distinct package
`com.reddraggone9.tandemlog.rc124`, owner-signed release124; installed version and
stable package identity/coexistence verified. Packaging-only variant from9cbc3fd,
not byte-identical public APK; app/native source is identical to published3a9e7d8
(the intervening changes are tests, documentation and qualification receipts).
Isolated private snapshot data copied and hashes verified; live household data
was not changed. Binding/usable launch remain pending Lee's first-use folder
picker, per his no-phone-UI-takeover preference: Documents →
Tandemlog-RC124-test → Use this folder, then Lee. No stable promotion.
