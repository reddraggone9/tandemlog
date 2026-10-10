# Food RC native acceptance

RC2026.10.4-rc.1/build57 is authorized for exact-artifact preview delivery.
Stable promotion requires Lee's acceptance. The
[source/evidence checkpoint](../evidence/food-2026.10.4-rc.1/README.md) and
[import contract](food-import-contract.md) separate app behavior from private
migration. Empty-inventory acceptance can finish before any source cutover.

Use the successful main signed-candidate run's original `android-release` APK
and original Windows installer/portable QA files. Record source commit, run,
version, archive digest, actual installer/APK SHA256 and public owner signer;
check the artifact's own metadata/checksums before installation. An archive
digest is not an APK digest. Publication reuses accepted bytes without rebuild.
Retain packaging lifecycle reports and portable member provenance. A Linux
window or cross-build is not Windows/Android runtime acceptance.

Use existing verified synthetic QA profile/folder paths only. Preserve their
pre-upgrade Task records/full state, profile writer, settings, guard identity and
folder/provider selection. Do not use live synced data, import private rows,
reset a profile, delete a vault or make final cutover a prerequisite. Parent
coordinates actual storage paths and any separately authorized private staging.

Bounded affected workflows on each native platform:

1. Install/launch the exact candidate and upgrade a synthetic stable56 profile.
   Verify Tasks/settings/selected folder survive and Food starts empty. Switch
   Tasks→Food→Tasks while offline; existing Task capture/edit remains usable.
2. Add two "Synthetic Rice" containers, brand "Sample Foods", calendar expiry,
   nominal size and location "Freezer". Inspect physical details, change one to
   partial contents, remove that observed container, restart cold, and restore
   it from Deleted. Compare actual physical IDs/fields and canonical bytes;
   verify the unrelated Task state remains intact. One full collapsed container
   has no redundant quantity; partial, unknown, multiple and mixed stock keep
   their summaries. Inspect still exposes explicit Full/quantity details.
3. Check Inbox with no expiry and retained stock with a reason. Verify normal
   phone/desktop layouts plus enlarged text, readable core labels/actions,
   keyboard focus/Enter/Space/Back as relevant, and field-specific semantics.
   Check the unavailable repeating Task control: uniform vector opacity,
   preserved disabled action and explanation. Optional broad assistive
   technology/spoken-audio expansion is not a gate.
4. In a backed-up synthetic folder, introduce a Food-only malformed/conflict
   stream. Verify Food reports its scoped failure while Tasks remains writable;
   restore the exact synthetic bytes and Retry Food. Separately reproduce a
   shared manifest/guard failure with an unsaved Task draft: all writes stop,
   draft survives, repeated Retry is read-only, and exact restored admission
   enables Save. A missing initialized guard remains blocked. Preserve the
   original snapshots; do not overwrite receipts or silently repair history.
5. Android: reopen after process death and retain the same SAF grant/provider
   selection; perform existing affected remote-replacement/provider and startup
   checks. Windows: retain exact installed/portable payload identity and finish
   applicable installed lifecycle/path/dialog/startup checks. Capture concise
   actual-device/desktop demos with visible inputs and label platform/build.

Food ordinary `.foodlog` streams are ignored by separate older task-only
profiles; older global conflict handling may still stop on Food conflict copies.
Shared local-profile schema downgrade and simultaneous old/new app use of one
profile are unsupported. New Food history failures stay module-scoped; shared
owner/manifest/writer/recovery faults stop the whole workspace.

The generic import API has independently reviewed synthetic recovery tests.
A private adapter uses the currently open FoodStore, or the same profile owner
with the app stopped and its protected settings writer loaded. It never chooses
a source writer, resets identity or writes canonical streams directly. A
controlled immutable plan, dry-run and explicit commit are required. Private
extraction, whitelist/provenance and live cutover are separate work.
