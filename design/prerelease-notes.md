Experimental RC4 task preview. Public prerelease, not Latest; stable 0.1.0 remains deferred.

New:
- Searchable multi-tag selection with removable chips. Tasks match any selected tag, intersecting other filters; workspace search still pauses/restores filters.
- Direct task editing without task overflow menus, a wide side editor and protected in-session drafts. Live validation, relevance-based occurrence controls and reordered schedule fields.
- Explicit bulk selection/edit/delete and constrained block dragging with edge scrolling. Untouched mixed fields remain unchanged; bulk edits exclude title/notes. Confirmed deletion retains canonical tombstones and independent recurrence successors.
- Actual Linux Flatpak and unsigned per-user Windows installer, with exact installed launch/replacement/uninstall/data-preservation/reinstall gates.

Compatibility: same application ID, owner Android signer, protocol v2 and cache format7 as RC3. RC4 opens valid RC3 folders. Upgrade every participating app BEFORE using deletion or assignee edits: RC3 readers reject new event/field types explicitly. Do not remove shared logs to accommodate an older app. RC2 protocol-v1 folders remain unsupported and preserved.

Linux: install the unsigned `tandemlog-linux-x64.flatpak` with `flatpak install --user ./tandemlog-linux-x64.flatpak`; run `flatpak run com.reddraggone9.tandemlog`. GNOME50 runtime resolves from Flathub, so this is not an offline-only bundle. Native default profile/data location is retained. Custom sync folders may require portal selection or a scoped folder grant; do not relocate a permanent share or grant whole-home access. See repository packaging/README.md.

Windows: run `tandemlog-windows-x64-unsigned-setup.exe`. Installs per-user without elevation; unsigned warnings are possible. Setup checks Microsoft C++ x64 runtime against the compiler version. If absent/old, setup stops with Microsoft's official download link; runtime installation/terms are not automated. Uninstall preserves profiles/shared data. Hosted native lifecycle smoke complements Linux visual QA, not full manual Windows acceptance.

Android: universal non-debuggable APK signed by the retained owner identity, with increasing build19 and same package. Exact APK must pass native acceptance before publication; no rebuild after acceptance. API30 emulator evidence does not cover every real phone/API36/provider. Back up the complete external canonical folder before uninstall; private settings/cache/writer/grants are not synced.

Bulk writes are independently durable per task. A failed operation can partially apply: the app refreshes/reconciles before retry and reports remaining tasks; it is not one all-or-nothing transaction. Dirty drafts are protected during this session, not persisted through process termination. No deletion recovery UI, notifications, private spaces or future modules are included. Users are attribution, not access control.

Markdown remains authoritative throughout prereleases. App tests use copies; stable cutover requires a coordinated fresh import and separate acceptance. No migration tooling or source formatting metadata ships in the app. Preserve full canonical manifests and every writer log; never delete history to fix cache/signature/access errors. Unknown/invalid history fails explicitly.
