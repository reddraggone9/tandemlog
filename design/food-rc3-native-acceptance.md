# Food RC3/build65 — exact Android acceptance handoff

Candidate source is `16cb07d62b3b6ef8432120debf45192c3b522ecd`, run
[38152037169](https://github.com/reddraggone9/tandemlog/actions/runs/38152037169).
Original archive identity, owner-signed APK hash and full hosted gates are pending;
use the eventual verified original APK, without rebuilding. This document does
not claim installed Android acceptance. [Source evidence](../evidence/toolbar-2026.10.4-rc.3/README.md)
records scoped actual Linux checks and independent reviews.

Use disposable synthetic data and the locally coordinated fresh trial only.
Keep live synced data and the old trial/receipts intact. Existing initialized
synthetic RC2 workspaces with numeric contents can exercise retained-data upgrade.
An old uninitialized manifest or any all-null Food history/protected receipt
requires a distinct fresh path, workspace/profile identity and immutable Full
plan. Do not rewrite payloads, receipts, hashes or folder-to-UUID bindings.

## Fresh importer preparation

Create an empty authorized folder without `tandemlog-space.json`. Open it through
the admitted current profile owner and installation writer:

```dart
final engine = NativeTextEngine();
final tasks = await TaskStore.open(
  folder,
  privateRoot,
  profileDatabase: admittedProfile,
  writerIdentity: settings.writer,
  textEngine: engine,
  initializeNewWorkspaceText: true,
);
final food = await FoodStore.open(
  folder,
  profile: admittedProfile,
  installationWriter: settings.writer,
  space: tasks.space,
);
```

Retain the engine for the store lifetime and close Food/Tasks before disposing it.
The ordinary checked initializer must finish before Food import; do not write a
manifest or text baseline directly. Prepare a new immutable plan using returned
`tasks.space`, a fresh import UUID and unchanged source provenance. New Full
contents are explicitly `{numerator: 1, denominator: 1, unit: null}`; explicit
fractions/measured amounts remain exact and blank nominal size stays independent.
Call `dryRunImport(plan)` before the separate authorized `commitImport(plan)`.
The [import contract](food-import-contract.md) retains exact retry and receipt
rules. This recipe does not authorize a live import.

## Focused installed checks

1. Bind the verified original APK hash, package, owner signer, RC3 version/code65
   and nondebuggable state. Upgrade an initialized synthetic RC2 profile and
   check retained settings, SAF grant, writer, Tasks/Food IDs and canonical bytes.
2. Create a genuinely new synthetic folder/user through the actual app. Capture
   and edit a task, confirm Settings has no shared-text setup tile, then cold
   reopen. Check initialized text remains editable and navigation/cold replay
   appends no canonical records. Rehearse the updated private trial initializer
   separately against the new folder; report that evidence separately.
3. Compare Tasks/Food Add/Undo/Filter controls in both themes at normal width and
   320dp/200% text. Check shared target sizes/colors/vertical alignment, narrow
   icon-only and wide visible Undo, active6px filter dot and accessible labels.
   Check full account identity and working Settings access. Food retains its
   existing desktop900px content cap; account label widths can differ above it.
4. Search across saved view/reason/Brand/Location filters using active and deleted
   matches. Check active order, sticky Deleted heading, muted struck deleted
   title and explicit Restore. Clear Search and verify saved filters return.
5. Type Brand/Location suggestions and arbitrary new text using the actual IME.
   Include suggestions drawn from deleted Food. Save/reopen and Cancel/Discard;
   check values are neither catalog-constrained nor forcibly normalized. Select
   multiple Brand/Location filters: OR within each field, AND across fields,
   empty field means any; Search bypasses them.
6. Select matching active containers and deselect one for a partial selection.
   Verify count, mixed Brand/Location initially untouched, field-specific Apply
   labels and explicit Clear. Save Brand only and verify exact selected physical
   IDs, unchanged Location/other fields and one Undo. Exclude hidden/deleted and
   later-arriving containers. Verify no-op/Cancel append nothing, and selection
   resets on Search/filter/workspace changes. Exercise newer peer field edits
   before Undo and confirm they survive.
7. Inspect expanded contents at320dp/200%: numeric Full/fractions/amounts,
   ordinal accessible actions, no visible opaque IDs or duplicate count, lower
   overflow/Inspect and48px targets retained. Confirm no Unspecified menu option.
   Check date label/value insets with an empty focused field and a populated
   date; open the shared calendar and return/save without losing the selection.

Record actual Android OS/device, exact APK, observations, canonical/integrity
checks and a demonstration with Show taps. Restore synthetic test settings and
stop temporary services. Linux source/component evidence, old RC2 acceptance and
static signing checks do not substitute for this installed affected-flow gate.
No unrelated historical matrix needs a new local rerun. Preview publication
remains held for accepted exact binaries and coordinator clearance; stable
promotion requires Lee's acceptance.
