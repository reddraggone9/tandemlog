Experimental RC10 task preview.

- New desktop setup uses a clearly named shared-data folder. Existing folder selections stay unchanged.
- Raw captures group in Inbox until a saved edit. Canceling keeps Inbox; Undo restores it.
- Search and Add fit the compact header while preserving drafts and Undo access.
- A profile-wide instance lock protects preferences and writing. The installation keeps one local writer identity across data folders.
- Android imports use directory notifications and persisted byte checkpoints to avoid rereading unchanged seekable logs on ordinary launch/resume. Providers without size/seek support retain a conservative fallback.

SQLite upgrades locally; canonical protocol and logs are unchanged. Checkpoints intentionally defer detection of same-length historical rewrites until full verification. Sync is not backup. Windows installer is unsigned; Android uses the retained owner signing identity. This is an experimental prerelease, not a stable release or Markdown cutover.
