# 2026.11.2-rc.1 / build117 — candidate preparation

Qualified and exact candidate accepted with disclosed coverage gaps; not published yet. Stable remains 2026.11.1/build116.

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
analyze clean, full Flutter suite **1919 passed**. Final integrated Python tools **310 tests OK (2 skipped)**. The package-path and
schema-v2 host preparation regressions fail before the fix and pass after it.
Shell syntax and git diff checks pass. No app Dart changed after the 1919-test run.
Logs retained privately at /home/nibbler/rc117-{format,format-tools,analyze,unit,python-initial}.log.

## Exact signed candidate and native acceptance

Candidate [43482661551](https://github.com/reddraggone9/tandemlog/actions/runs/43482661551)
and main CI [43482632158](https://github.com/reddraggone9/tandemlog/actions/runs/43482632158)
pass completely at source518be438, including reference receipts. Download waiter
terminal success and complete inventory/checksums/provenance/signer/version gates
pass. Four artifacts are accepted; APK SHA256
`5cc396e3ceddd825b025de2e6be5ba8fe179a9b14b4680d75b1a0db88aa5b2a2`.

Retained synthetic stable116->exact117 upgrades pass preservation, binding and
integrity; Android SAF preserved. GTK17 native semantic checks and Android12
assertions pass, with saved workflow reviews/captures. Both labs stopped cleanly;
GTK has5 clean exit files plus2 selection-review exits. Search clears selection,
manual Add requires expiration, hand-entered dates are confirmed: these are the
accepted source contract, not regressions against mistaken preparation assumptions.

Receipt-import GUI was not exercised: GTK uses exact installed Flatpak bundled
CLI plus native display; Android exact-source production APIs on private synthetic
canonical copy plus peer replay/native display. No Windows GUI claim (hosted native
lifecycle and portable verification only). See [native evidence](native/README.md)
and native/native-acceptance-summary.json for all coverage and limitations. No
physical devices or live data touched, no seeds or stable promotion.

## Remaining before handoff

Four-asset prerelease publication and anonymous public verification are pending.
Format-changing RC needs separate non-synced data copy/profile and portable ZIP on
Leela, preserving stable. Private preparation scripts/runbook are ready, but device
staging and usable-launch verification were not performed: this assignment
prohibits touching Lee's devices/live data. Do not describe it as ready to test.

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
each platform; Windows Flutter:1909 passed/10 skipped. The later signed candidate passed its complete matrix and exact-artifact
acceptance with the coverage qualifications above.

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
