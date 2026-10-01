Experimental task-parity preview. This is a public prerelease, not Latest or a stable release.

**Breaking prerelease boundary:** the application identifier is now `com.reddraggone9.tandemlog`, and protocol v2 requires a new data folder. Android installs separately from rc2; Windows uses a new local profile. Keep existing Markdown and complete canonical folders. Do not point the migration tool at live data or delete an old folder to resolve an error. Stable compatibility promises begin at 0.1.0; no in-place prerelease conversion is provided.

New in rc3:

- Separate start, scheduled and due dates, each with optional time. Choose Local or a shared pinned IANA zone (including UTC) for the task schedule. Omitted times retain date-only precision. Invalid start-after-due values fail without discarding the editor draft.
- Scheduled-first date groups and start-time availability update while the app stays open. Optional sort-date bounds move the displayed day without changing deadlines and preserve precise time within that day. Native time/zone signals plus a foreground fallback recompute the view.
- Tags with a searchable bounded picker and a consolidated filter menu with visible nondefault/reset state, constrained drag with edge scrolling and accessible move-up/down ordering within equal effective date/time keys, and the 37 observed Obsidian Tasks recurrence expressions. Completion creates one successor atomically. Scheduled dates/times are removed according to the selected source behavior; the successor precedes completed history. Reopening or Undo preserves the next occurrence and its work; recompleting history does not create another successor.
- Show upcoming is off by default and makes future-start tasks editable. A scheduled date without recurrence warns without clearing the value. Known obsolete local caches rebuild from validated logs while preserving writer identity and a private backup.
- Spaced responsive onboarding/settings actions, compact task headers with top-bar identity/settings, and immediate caret visibility after Shift+Enter. Large-text editor controls wrap; the everyday task list stays compact. Wide rows place metadata beside titles; narrow layouts retain secondary metadata, with a separate description preview only when present. Dates already stated by the group heading are omitted; times, zones and differing original dates remain.
- The original wall-clock/causal event ordering is restored: max(current nanoseconds, highest seen clock + 1), encoded as an exact decimal string. Imported clocks are immutable. A materially future clock warns but does not block writes; bad future clocks can propagate. Automatic history repair is not implemented.

Linux: extract the entire x64 bundle and run `tandemlog`. Built on Ubuntu 24.04; requires a compatible glibc, GTK 3, C++ runtime and graphical session. On Ubuntu 24.04 the runtime packages are `libgtk-3-0t64` and `libstdc++6`. Keep `lib/` and `data/` beside the app. Linux is the primary desktop visual QA target.

Windows: unsigned portable x64 ZIP; extract everything and run `tandemlog.exe`. Hosted Windows builds/tests are required, but do not establish interactive Windows UI acceptance. The Microsoft Visual C++ runtime may be required; unsigned-app warnings are possible.

Android: universal non-debuggable APK signed by the retained owner identity. The release gate requires native validation of the exact APK hash before publication; the public artifact is not rebuilt afterward. Android uses SAF folder selection. API 30 emulator evidence is narrower than real-phone/API 36/provider coverage; BasicSync and other transports need device-specific testing. Back up external canonical folders before uninstalling any earlier app; local settings, grants and caches can be lost.

Task users are attribution, not access control: a folder is all-shared. No notifications, deletion, durable drafts, private spaces or future modules are implemented. Unknown/invalid history fails explicitly without silent deletion. Checksums accompany all platform bundles; the owner Android certificate fingerprint and source metadata accompany the APK. Stable-only clients have no stable build available yet.

Markdown remains authoritative during prereleases. Testing uses copies in the permanent sync folder; only test contents are disposable. The private one-time migration tooling is separate and is not shipped or supported as an app feature. Stable cutover requires a coordinated fresh snapshot/import and explicit approval.

Filter state lasts for the current app session; it does not change shared task facts. Reset restores active-user Open tasks with upcoming hidden and no tag filter, preserving the active identity.
