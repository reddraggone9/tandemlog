# Recovery and known boundaries

The [current action format](schema.md) is under validation. [Earlier recovery instructions](archive/recovery-before-coordinated-cutover.md) retain their original released-source attribution.

- Stop edits and preserve the canonical folder before manual repair. Sync is not a backup.
- Restore missing/changed committed history from an intact copy. Do not hand-merge logs or hide conflict copies.
- Unknown complete kinds/revisions require a compatible app. Both modules stop before continuing writes.
- An unterminated suffix is uncommitted. A nonowner ignores it unchanged; before a new action its owner may compare/truncate only that suffix. Refresh/preview do not clean it. Complete invalid newline-terminated records remain corruption.
- Same-session uncertain writes retain exact in-memory bytes/native ownership. Restart forgets unfinished intent. A complete append may already have succeeded; inspect the model before repeating an action.
- A provider without safe suffix truncation refuses the next write after restart. It does not replace a committed prefix. Actual Android grant/provider behavior still requires native acceptance.
- Reselect the same original Android tree after grant loss. A new path or replaced manifest does not prove workspace identity.

The exclusive local DB stores installation identity, preferences and acknowledged common observations as well as disposable projections. Do not clone that profile onto another active device or delete SQLite as a cache reset. WAL/recovery sidecars belong with a stopped profile during investigation. Current/future damaged authority fails closed.

The coordinated cutover deliberately retains simple settings and resets other private state, including drafts/pending saves. Full stopped-profile collection is optional precaution, not a prerequisite. Accepted frozen canonical originals, explicit mapping and separate live-cutover approval remain necessary. No implementation or QA instruction authorizes a real reset.

A separate process-scoped TANDEMLOG_PROFILE selects separate Tandemlog app data, not a new Windows user. Moving just SQLite does not isolate settings, writer identity, native caches, WAL/SHM and instance ownership. Confirm actual native/Flatpak roots rather than assuming they share data.

No automated backup/repair UI, encryption, compaction or universal provider guarantee is claimed. A process crash typically leaves an incomplete suffix; power/storage failure can also damage a complete record. Integrity checks must preserve that evidence. Deliberate loss of the entire private profile also loses its older trusted-head baseline.

## UX brief: startup, open failure and "Update Tandemlog" (Lee 11-03)

Checked against [ux-principles.md](ux-principles.md). Each state answers one
question and says nothing it doesn't know yet.

- **Opening** ("is it working?"): the app name and an indeterminate progress
  bar, nothing else. No onboarding or error copy while the workspace opens;
  opening runs in bounded slices so the bar keeps moving.
- **No folder set** ("what is this, what do I do?"): the existing onboarding
  (headline, one line, Start / Choose an existing folder). Only here.
- **Open failed** ("what broke, what can I do?"): title "Can't open your data
  folder", one line that the data wasn't changed, the error, then Try again and
  Settings. No onboarding headline.
- **Newer data** ("why did it stop, what do I do?"): another device saved data
  this version can't read. Title "Update Tandemlog"; body "Another device saved
  changes with a newer version of Tandemlog. Update this device to keep going;
  nothing was lost."; a filled **Update** button that opens the platform's
  update (the releases page; the Flatpak and Scoop channels when they exist);
  a collapsed **Technical details** with the exact message and a copy button.
  Shown at startup and when a sync brings such data in; the real corruption
  screen (integrity failure, Retry and Settings) stays separate. The required
  version isn't named: records don't carry the writer's app version.
- Left out: stack traces, internal record numbers outside Technical details.
