# Stable 2026.11.1/build116 published

Lee accepted RC115 on his physical Android phone on 2026-11-07 at 15:19 CST: “Looks good. Let’s publish that as stable. You can remove that test app and data.”

Candidate changes are version/AppStream metadata and documentation only relative to accepted RC115 f5e95008; runtime code is unchanged. Reuse sealed q16 through verified relevant-source identity, not a new timing run. All candidate and exact-artifact native/publication gates remain required. The phone trial used a packaging-only side-by-side release variant; it does not replace original-artifact lab acceptance.

README reviewed against released workflows; Activity overview updated. Stable notes retain the reviewed RC body and all five real-app images. Windows runtime qualification remains the existing installer lifecycle/inventory coverage, not a new manual GUI claim. Candidate, native and public receipts are linked below.

## Completed release

[Stable2026.11.1](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.11.1), release437867625, published2026-11-07T21:53:00Z as immutable Latest from `ef71b8806fb93da3a9d2ce82f3610e86d044f05e`. Signed candidate42415487006 and automatic push CI42415472687 passed attempt1. q16 qualification reused after exact identity verification; no new timing run or override.

[Candidate verification](candidate-verification.json) binds all four original payloads, stable version116 and the pinned owner signer. [Native acceptance](native-acceptance-summary.json) covers retained Android and GTK115→116 upgrades, byte-identical canonical/local profiles across installation, SAF/binding continuity, retained Tasks/Food/Activity, synthetic writes, cold reopen, append-only history and clean shutdown. GTK logs retain shutdown warnings; both normal exits were0. Windows installer lifecycle/inventory evidence remains the existing qualification, not a new manual GUI run.

Independent source/editorial and final artifact/native reviews passed. Stable notes retain accepted RC115 prose and all five media images, with relative links resolved to immutable accepted-source URLs. The existing immutable-release draft method ran the same candidate-source, publication and asset gates as stable.yml, attached and verified all four original assets before finalization, and did not rebuild or relabel RC artifacts. [Anonymous public verification](public-verification.json) confirms payload hash/size, exact notes and five image bytes, tag/source/Latest, and all51 prior releases/tags unchanged. [Public APK signer/version](public-apk-verification.json) passed.
