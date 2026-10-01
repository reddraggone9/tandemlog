# Decision 0004 — editing, bulk actions and desktop installers

Status: accepted RC4 scope, 2026-10-01. Acceptance: [status](../status.md), [UX audit](../ux-audit-rc4.md).

Lee requested multi-tag filtering, direct editing without task overflow menus, a wide side editor, bulk actions and desktop installers. These extend the [compact interface](0002-onboarding-and-everyday-interface.md) and retain [date/manual ordering](0003-task-parity-and-prerelease-boundary.md).

## Interaction

Selected tags match **any** selected tag, intersecting with assignee/completion/upcoming filters. Removable chips and a bounded searchable result list expose selection. Search pauses/restores filters. No general query framework.

Rows open editors directly; identity/Settings stays in the top bar. Wide layouts keep the list beside the editor; smaller layouts use a modal. Protect dirty drafts on close, task/user/workspace/filter changes and responsive transitions. Drafts are in-session, not termination-durable. Validate changed inputs immediately without pristine errors. Schedule order: Start, Due, Repeat/This occurrence, Time zone, Sort bounds. Hide irrelevant occurrence controls but preserve contextual access to existing/draft nonrecurring overrides.

Bulk editing excludes titles/descriptions. Preserve mixed values unless explicitly applied; an applied blank clears. Tag deltas preserve unrelated membership and unseen additions. Validate every resulting schedule before the first append. Deletion is confirmed and permanent; a recurring successor remains independent.

Bulk drag preserves selected tasks' global relative order and hidden ranks within one completion section and exact effective date/time bucket. Show invalid destinations during dragging, retain edge scrolling and revalidate on incoming/time/filter changes. No implicit date changes or unrestricted manual-sort mode.

## Persistence

Bulk writes are independently durable per task, not one transaction. Prevalidate the selection, report partial progress and reconcile uncertain appends before retry. Retain the remaining draft. Expected snapshots prevent silent overwrites of changed state.

Protocol v2/cache 7 remain. Additive `task.deleted` and assignee edits read RC3 input, but RC3 rejects these new records/fields explicitly. Update every writer before using RC4 actions; never remove records for an old reader. Tombstones remain canonical history.

## Distribution and alternatives

Use Linux Flatpak and an unsigned per-user Windows installer instead of loose archives. Retain identity, Android signer, native profile and sync-folder path. Flatpak grants rendering/IPC and specific native profile paths, not home/host/network. Custom folders require scoped access. Windows uninstall removes program files/shortcuts, retaining data.

Hosted gates install/launch/replace/uninstall/reinstall exact candidates with synthetic data. They complement Linux visual QA and exact-APK Android acceptance; manual Windows and provider coverage remain separate. [Packaging commands/limits](../../packaging/README.md) disclose prerequisites. No Store/Flathub publication, paid runner or new credentials.

Rejected for now: universal filtering, unrestricted date drag, replacing untouched mixed fields, deleting a recurrence series through one occurrence, and automatically discarding drafts. Revisit after concrete hands-on friction.
