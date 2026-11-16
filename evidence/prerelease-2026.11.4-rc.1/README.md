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
completion successors and exact historical bytes. Compatibility recheck pending.

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

## Qualification, candidate and delivery

Pending final development CI, controlled reference qualification, signed candidate,
exact Android/GTK upgrade acceptance, anonymous public verification and isolated
trial handoff. This file is not an acceptance receipt until those are recorded.
No live household data used or changed.
