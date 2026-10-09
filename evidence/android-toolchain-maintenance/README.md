# Android toolchain evaluation evidence — 2026-10-09

Application source: `43d49d9b027aad099a7aa8e3e77ba4c01ab2b3ce`, based on
`d93b6329c91559051d46915fc7a8114d17565cb8`. Later evidence commits do not
represent a different compiled application. See the [review](../../design/android-toolchain-maintenance.md)
for compatibility, source review, host accommodations and acceptance limits.

- `artifact-provenance.json` records successful official source/POM/binary
  downloads; it is a reviewed candidate inventory, not a claim every artifact
  was selected or executed. Exploratory unavailable coordinates are excluded.
- `allowed-runtime-hashes.json` and `evaluation/observe.gradle` are the exact
  private evaluation guard. The script is not installed by CI or application
  builds. It filters selected versions and checks filename/hash pairs; it does
  not enforce full group/repository provenance or the whole dependency closure.
  Loaded plugin observation follows evaluation; prior source review provides
  the initial execution gate.
- `*-selected-scopes-*.jsonl` records effective selected artifacts, plugin
  origins, embedded R8 identity and actual selected task implementation classes.
- `android-*-receipt.json` binds debug APK/signing/native-library identities;
  the APK bytes remain private in this cloud checkout. `cold` means the first
  successful application package after private bootstrap/setup/guard retries,
  not a pristine empty-cache proof. `warm` is the immediate repeat.
- Local test logs (trailing whitespace normalized) and `local-validation.json` preserve passed checks and
  unchanged pins. Source/native review receipts are focused review evidence,
  not exhaustive upstream audits or reproducible-binary attestations.

These debug receipts establish local package checks. Owner-signed release
shrinking, exact Android runtime/SAF/provider workflows and native lab
acceptance remain separate. No live application data was used.
