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
