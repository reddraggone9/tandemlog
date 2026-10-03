Experimental 2026.10.0-rc.1 task preview.

- New desktop setup uses a clearly named shared-data folder. Existing folder selections stay unchanged.
- Raw captures group in Inbox until a saved edit. Canceling keeps Inbox; Undo restores it.
- Search and Add fit the compact header while preserving drafts and Undo access.
- A profile-wide instance lock protects preferences and writing. The installation keeps one local writer identity across data folders.
- Android imports use directory notifications and persisted byte checkpoints to avoid rereading unchanged seekable logs on ordinary launch/resume. Providers without size/seek support retain a conservative fallback.
- Task titles and quieter details now share a line when they fit and wrap naturally when they do not, including narrow screens and larger text.
- Settings includes **Check data integrity**, with a full canonical-chain check and a copyable diagnostic report. Checks do not repair or rewrite data.

**Prerelease format break:** canonical JSONL now uses v3 with embedded per-record SHA-256 predecessor/current hashes. Existing v1/v2 folders are rejected and preserved; no automatic conversion, folder reset or deletion occurs. Coordinate test-folder backups/reset separately or use a separate v3 test folder. Markdown remains authoritative until the separately agreed stable cutover.

Ordinary startup remains incremental; checking the old prefix requires the Settings action or a fresh full rebuild. Hashes check consistency, not authenticity: a fully recomputed chain or removed final records can pass a fresh scan without a trusted prior head. Sync is not backup. Windows installer is unsigned; Android uses the retained owner signing identity. This is an experimental prerelease, not a stable release.
