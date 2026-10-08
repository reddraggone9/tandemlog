# Completion confirmation progress

The parent-completion command retains its admission/shutdown guard while an
unfinished-checklist dialog awaits a decision. The header now hides progress
during each consent dialog, including renewed consent after incoming changes,
and shows it during the actual post-confirmation write. The checklist command,
canonical records, snapshot validation and session Undo are unchanged.

Each dialog accepts one answer. Repeated or retained answer callbacks cannot
pop the underlying task page or a later dialog.

The frozen native red observes an indeterminate header indicator while the
six-item consent is open. Five native regressions pass Cancel, barrier, Escape,
stale renewed consent, repeated checkbox/answer callbacks, held real append
progress and failing append cleanup. Nineteen focused completion tests and the
two existing desktop/narrow enlarged native checklist workflows pass. Analyzer
reports no issues. Independent correctness review accepted the final dialog
guard with no must-fix.

`before.png` and `after.png` are inspected raw screenshots of an actual native
GTK application at 1200×850, Dark, 100% text, using the same synthetic six-item
fixture. The local baseline is release-mode source4434440; the local fix is
debug-mode. The baseline shows a teal segment beneath the header; the fix has
none while the same dialog awaits input. Both cancellations leave all fixture
canonical bytes unchanged. These are local native comparisons, not published
installer acceptance. The integration renderer's separate test-starting image
was not used as app visual evidence.

The exact code hash, raw result and media hashes are in `verification.json`.
Windows/Android acceptance is coordinated with the subsequent approved inline
checklist work; no release or stable promotion is performed here.
