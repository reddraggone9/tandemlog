# 0021 — Local section memory and Android launcher shortcuts

Status: accepted scope from Lee's next-RC instructions, 2026-10-12; implemented and published as experimental 2026.10.5-rc.1/build75 on 2026-10-13. Stable 2026.10.4 remains Latest. [Publication receipts](../../evidence/prerelease-2026.10.5-rc.1/publication/README.md) bind the accepted original artifacts.

Reopening returns to the last successfully visited Tasks/Food section on this device. A cancelled draft guard leaves the draft and remembered section alone. Android offers two explicit launcher destinations, which override the saved preference and wait for workspace and user setup. Newer explicit navigation takes precedence over delayed startup and setup fallback.

Store optional `lastSection` (`tasks` or `food`) in the existing LocalSettings JSON in `protected_settings.raw` of `local.sqlite`. Missing or unknown values behave as Tasks. Preserve unrelated JSON values and protected writer identity. No schema change, new preferences file, canonical event or synced preference is introduced. [Storage contract](../storage-and-sync.md) owns persistence.

The host owns readiness, coalescing, editor guards and successful preference writes. Opening, closing and saving editors are temporary blocks; their completion wakes the queue. Actual Cancel clears coalesced requests. The native adapter only accepts constant destinations and deduplicates initial/warm delivery. Restored activity/task history is not a fresh shortcut request.

Publish fixed-ID dynamic Android shortcuts with `SINGLE_TOP | CLEAR_TOP` so warm navigation retains the existing activity and its drafts. Ignore `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`, which Android uses to restart an old task base intent, and skip initial consumption on activity restoration. Supported launchers may pin these shortcuts themselves. No new permission, persistent service, automatic pin request or launcher-specific API is added.

Rejected: synchronized section preferences; another preferences file; static shortcuts that reset activity tasks; interpreting a temporarily unavailable editor as Cancel; setup fallback overwriting newer navigation. Revisit if new sections or deep links require more destinations.

Food keeps Stock/Retained/Deleted choices. More filters… contains Brand and Location and, only in Retained mode, Retention reason with All reasons when empty. Searchable suggestions, chips, active dots, row reasons and search bypass remain. Add and Add another omit retention; Edit retains it. Secondary metadata/checklist notes use existing secondary colors, preserving primary text and semantic expiration/error colors. Android, Windows and Flatpak share the established green-square white-checkmark icon.

Native launcher/Recents, actual packaged icons and themed/enlarged UI acceptance completed before publication. Detailed native evidence remains private and preserves its explicit slow-save timing, scoped visual/IME/recording and Windows GUI qualifications. Widget tests and source review do not substitute for observed native gates. Base64 SIMD remains an optional separate investigation, and its current pin is unchanged.
