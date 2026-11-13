# 2026.11.2-rc.1 / build117 — candidate preparation

Not published or qualified yet. Stable remains 2026.11.1/build116.

## Scope

Linear integration from stable main, including current docs, Food Keeps for
(b38528b), cooperative workspace-open stages and large-text task editor
(b31b23a), and shared Repeat-list grammar (91ad0dd). Reusable publication/verification and qualification helpers are now in tool/. No seed values or larger
validator-off-isolate rewrite are included.

## Compatibility review

Keeps for adds product.edit revision2 and container.add revision3. The previous
stable reader refuses these records fail-closed; earlier history keeps its
meaning. Frozen fixtures, deterministic replay and the previous-reader native
check are documented in design/food-shelf-life.md. Repeat-list spellings use
the existing task revision4 boundary. There were no textual integration
conflicts. A format-changing RC requires an isolated Leela workspace/profile;
no live cutover or stable promotion is authorized by this release.

## Local checks

Integrated app: format clean (508 files across lib/test/integration_test/tool/bin),
analyze clean, full Flutter suite **1919 passed**. Final integrated Python tools **309 tests OK (2 skipped)**. The package-path and
schema-v2 host preparation regressions fail before the fix and pass after it.
Shell syntax and git diff checks pass. No app Dart changed after the 1919-test run.
Logs retained privately at /home/nibbler/rc117-{format,format-tools,analyze,unit,python-initial}.log.

## Pending

Notes/media and tooling independent review, CI, controlled reference
qualification, native cold-start receipt, signed candidate, exact native upgrade
acceptance, four-asset prerelease publication/public verification, isolated
Leela handoff. No release acceptance is claimed by the local suite.

## Release tooling review

Independent review identified missing prerelease channel support and note/main/media
provenance checks in the initial migration. Corrected before CI: RC finalization
sets prerelease true and Latest false, stable requires existing Lee acceptance,
notes come from live main and image links pin that commit and exist before draft.
All 24 targeted release-tool tests pass. Prior public-state freeze used the new
tool (52 releases/tags, Latest v2026.11.1). No publication is claimed yet.

## Controlled qualification and formal native startup (2026-11-13)

Final changed-source CI [43468510127](https://github.com/reddraggone9/tandemlog/actions/runs/43468510127)
passes all nine non-reference jobs: Linux, Windows, Android, hosted AOT correctness,
four native workflow shards (274 cases total), and their exact-union verifier.
The pre-receipt reference job alone is expected red. Hosted Python:310 tests on
each platform; Windows Flutter:1909 passed/10 skipped. The signed candidate still
needs its own complete matrix and exact-artifact acceptance.

Qualification q17 (`76fe0f5e24537af72e12d1680fe588ba`) binds2090994 and
relevant-source-v3 `2afefe81ee6b52335b0f11670b5eb32f454be599c61b3f9552deb44cef417172`.
It remains valid after the Windows test-fixture-only6de9d1f change. All261 labels
across3 shapes (783 observations), both history-growth rule sets, correctness,
input pins and cleanup pass. Three first-pass misses cleared the gate's automatic
same-invocation fresh-process confirmations; zero confirmed failures. No manual
timing retry. Actual enforcing run18:18:32–18:21:39 UTC; clean completion18:21:43,
within the original25-minute deadline, no owned processes, swap or OOM events.

Formal native `native.coldStart.firstList`:490ms median under1000ms; five warm
starts520/510/480/480/490ms, strict first launch2800ms. Synthetic isolated workspace,
exact2090994 release build, private runtime/bus; no physical devices or live data.
Both committed receipt verifiers pass at the final branch HEAD.

See `qualification-summary.json`, `qualification-registration-review.md`, and
`reference-native-preflight.md`; complete sealed receipts in
`../reference-performance/current/` and `../native-cold-start/current/`.
Pre-launch admission failures (not timing attempts) are retained privately: missing
reference label registration, Windows8.3-path test fixture mismatch, inherited
emulator/Gradle/privateADB5071, and quiet-host background readers/downloads.
Budgets and controller controls were not loosened. All temporary audit, Sonarr and
Transmission controls were restored and the maintenance fence released.
