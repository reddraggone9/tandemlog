# Bulk stale-save warning visibility follow-up

Status: isolated, independently reviewed fix; frozen signed build 46 remains
unchanged and unpublished. The branch is `fix/bulk-stale-warning-visibility`,
based on main `3111dd94510a8f77e6978aa177e8d9b44fd7607c`. Tests-first commit
`fc13df0` freezes the hidden-warning regression. Implementation is `2a7968d`;
the final native test and accurately captioned demo use
`d0ecbbb4aabbcb11a784eeda9735f2ecd30b87ff`.

## Observed problem and correction

After a peer changes a selected task, Save correctly rejects the old bulk draft.
The narrow modal previously put its failure in the heading, above the scrolled
form. The warning existed but was invisible at the bottom. The same real native
peer-change scenario fails the baseline visibility assertion at main311. Its
[baseline screenshot](../evidence/bulk-stale-warning/baseline-native/bulk-failure-narrow-dark-rejected.png)
and [corrected screenshot](../evidence/bulk-stale-warning/native-verified/bulk-failure-narrow-dark-rejected.png)
show the difference at the same actual 390×820 dark GTK window.

Bulk-modal failures now appear above the fixed actions. The message scrolls
independently when necessary; its bounds use the actual available editor height,
including the surrounding Scaffold's keyboard resize, and yield to wrapped
buttons. The live-region message appears once. Field validation, single-editor
placement and wide-panel placement are unchanged. No save/delete callback,
stale-selection guard, draft controller, durable record, native library,
dependency, workflow or version changed.

## Verification and evidence

Formatting and analysis are clean. All **55** focused editor, tag, date/time and
bulk-semantics widget tests pass. New cases retain the exact draft/caret value,
focus and form offset after delayed failure, verify independent long-message
scrolling and the live region, and preserve single-modal/bulk-panel behavior.

The exact final-source native GTK test passes **4/4**: desktop dark 1200×850;
narrow dark 390×820; light 390×820 at 200% text with a simulated 280px IME;
dark 360×640 at 200% text with the same simulated IME. A real synthetic peer
changes description through the production native adapter. Two rejected Saves
retain selection/draft and all canonical JSONL log hashes, preserve the peer edit,
write no schedule patch, and allow Cancel→Discard without canonical writes.
The native engine uses the adjacent built bundle rather than a library override;
its hash matches the unchanged reviewed library. Linux simulated geometry is
not Android keyboard or spoken accessibility evidence.

The [7.47-second desktop demo](../evidence/bulk-stale-warning/native-verified/linux-gtk-narrow-dark.mp4)
records a 1200×850 X11 desktop containing the actual narrow GTK window. Its
visible pointer identifies the scripted Save, retry, Cancel and Discard controls;
the permanent caption identifies Linux GTK debug and the scripted click flow.
The [receipt](../evidence/bulk-stale-warning/receipt.json) binds source, test logs,
screenshots, video and hashes. Initial investigation captures are retained and
are not substituted for final-source evidence. Independent correctness,
architecture/UX and security reviewers accepted the final source and final
runtime proof within this scope.

## Remaining viewport limit

At 360×520, 200% text and a simulated 280px keyboard, the actual app header
leaves only 160px for the editor. Its existing wrapped Delete/Cancel/Save controls
consume that space; the pinned warning has zero remaining height. The
[retained reproduction](../evidence/bulk-stale-warning/extreme-native-red.txt)
and [pixels](../evidence/bulk-stale-warning/native-diagnostic/bulk-failure-small-dark-200-ime-rejected-debug.png)
remain an explicit limitation. An earlier standalone enlarged-font probe with
Delete also overflowed at 240px usable height; its investigation log is retained.
This fix does not establish
universal very-small-window or landscape usability.

Owner: Tandemlog UI maintenance, coordinated by Lee. Revisit after actual
small-window/landscape Android use or before stable promotion. Exit condition:
reviewed host/header or action-layout change makes warning and recovery actions
usable at the reproduced dimensions, with native evidence and retained drafts,
focus and form position. Forced keyboard dismissal, focus transfer and form
scroll jumps were rejected because they would disrupt the interrupted edit.

## Candidate and acceptance implications

Parent reported exact owner-signed Android acceptance for run `37819214432`,
source `77a5f2dfde4ea914e7f2cf09dcbf77ee738056cc`, version
`2026.10.2-rc.4+46`, APK SHA-256
`465c123d91be4465296945aa6d576545cd17dd05329da338c013dd069f4a7a1d`.
The acceptance packet is Library `libfile_2254ff7abc188191b4075b190a0e4823`.
These are attributed parent findings; this consumer did not independently read
those APK/packet bytes. Parent's Windows/Linux archive checks were inert
byte/provenance checks. Windows manual interaction and Android spoken
accessibility remain unverified.

The visibility fix changes application bytes. Shipping it requires a fresh
monotonic build **at least 47**, rechecking actual floors, full CI, a new
owner-signed package, exact affected Android/native/manual acceptance and a
fresh quota check. Build46 acceptance cannot be relabeled as acceptance of this
fix. If included in a preview, release notes/media need independent review of
the resulting actual commit range. No merge, version bump, signing dispatch,
publication or stable feature promotion was performed for this follow-up.
