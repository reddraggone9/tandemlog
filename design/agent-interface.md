# Agent interface

Status: **Accepted direction (Lee, 2026-10-28 22:10 CDT); implemented on the
next release line, unreleased.** Lee: “For the separate binaries/logs for
agentic access, I think you've convinced me. Do what you think is best.”
[ADR0036](decisions/0036-agent-interface.md) records the choice and
alternatives. Section 11 records how the implementation answered section 9 and
where it differs from this text; the [feasibility record](agent-interface-feasibility.md)
holds the evidence.

## 1. Goal (Lee, 2026-10-28)

Make it easy for an LLM agent (mainly Vex, but not tied to OpenClaw) to read and
change Tandemlog data, with minimal configuration:

- LLM-friendly list and search output.
- Every user-facing write action, plus specific ones such as the YNAB
  receipt/purchase import ([Food products](food-products.md#5-method-prices-and-receipt-import))
  and product store links.

Constraints carried over unchanged: serverless file sync, attribution to the
writing installation, the one-release format rule, fail closed on unknown data,
no direct canonical-file writers ([food import contract](food-import-contract.md)),
and the performance contract.

## 2. Accepted direction in one paragraph

Ship one headless Dart executable, `tandemlog-cli`, built from the same source and
version as the app. It links the app's pure-Dart domain/storage/Food code and the
same native text engine, but not Flutter. Every command has terse text output and
compact JSON output. `tandemlog-cli mcp` serves the same command registry as MCP
tools over stdio. There is no network listener or separate service credential;
local account/profile permissions govern access. The GUI and CLI ship together
in the existing Flatpak, Windows installer and
Windows ZIP; there is no separate CLI download. Each agent identity has its own
installation, private profile and writer log, separate from the GUI and from
other agents. The profile joins the ordinary synced workspace. Identity is not
per machine, and there is no agent-count cap. Its writes are ordinary actions
attributed to that installation. The design targets **no canonical format
change**; that remains a feasibility constraint, not a proven result, especially
for whole-action text Undo across process restarts (sections 6 and 9).

## 3. Implementation feasibility (inspection at the design baseline)

1. **A headless binary is feasible.** `lib/domain`, `lib/application`,
   `lib/storage`, `food_store.dart`, `inventory.dart`, `food_products.dart` and
   `food_purchase_import.dart` import no Flutter. Flutter is limited to widgets and
   `lib/platform` (Android SAF and view-time plumbing). A Dart CLI build (`dart
   build cli` with native-asset hooks, or `dart compile exe` plus bundled
   libraries; verify in a spike against the pinned Dart 3.13.4) can ship sqlite3
   and `libtandemlog_text`. `_defaultLibrary()` currently resolves the
   library relative to the Flutter executable; the CLI injects its own path.
2. **A refactor is required first.** Workspace opening and command sequencing live
   in `lib/main.dart` (6,200 lines). That includes the open sequence
   (`UnifiedHistory.create/open` → `TaskStore.openUnified` → shared-text
   initialization → the `BoundedLogFolder` check → `FoodStore.openUnified` →
   occurrence migration), the pending-command retry and fingerprint guard
   (`_foodCommand`), and part of the Food view composition (Running low above
   Inbox, Search including Deleted, in `food_page.dart`). Move these into
   `lib/application/` (a `WorkspaceSession` plus pure view builders), and make
   both the app and the CLI use them. Otherwise the two will drift. This touches
   the app's hot paths, so it gets a normal reference qualification.
3. **Undo already works below the UI, with one exception.** `TaskStore.undoOperations(ids)`
   and `FoodStore.undoOperations(records)` retract canonical operations by ID, so
   a later process can undo an earlier one. Food only lets a writer retract its own
   operations. The exception is title/notes text: native text Undo is refused
   outside "its retained editing session". Section 6 covers this.
4. **Reusing Farnsworth's installation e52144b5 isn't recommended.** Its profile
   is a 32 KB `local.sqlite` in **Hester's** Flatpak data
   (`/home/hester/.var/app/com.reddraggone9.tandemlog/data/...`, mode 0600,
   hester-owned), last written 10-21, before the cutover. Reusing it would mean:
   running as Hester or copying her account's profile; a one-way upgrade of a
   profile the cutover deliberately preserved; mixing agent writes into the history
   that holds the historical importer and initial task import; and, if a GUI is
   ever installed for Hester on Farnsworth, Vex and that GUI fighting over one
   profile lock. The only gain is avoiding one more `.applog`. Purchase-import
   idempotency comes from source-derived purchase IDs in canonical history, not
   from a private ledger, so nothing ties imports to e52144b5. It would be safe
   only with exclusive ownership forever. The accepted direction is a fresh agent
   installation; do not reuse it.
5. **"A local copy" is the device's synced folder itself.** On Farnsworth that is
   the Syncthing hub folder `mypool/sync/tandemlog`, which is lee-owned (ACL
   lee/hester rwx), so Vex can append to its own file there. The CLI never writes
   any other writer's file, and staging names like `.syncthing.*.tmp` are already
   skipped.

## 4. Architecture

```
tandemlog-cli (dart build cli; no Flutter)
  ├─ command registry: name, JSON Schema args, read|write, renderer
  │     ├─ CLI front end: argv → registry; text | json | jsonl output
  │     └─ MCP front end (`mcp`): stdio JSON-RPC; tools/list from the registry
  └─ lib/application/WorkspaceSession (shared with the app)
        UnifiedHistory → TaskStore / FoodStore → pure view builders
```

- **One registry.** It produces argv parsing, `--help`, `tandemlog-cli schema`
  (machine-readable list of commands with JSON Schemas) and MCP `tools/list`.
  The app and the CLI cannot expose different action sets without a test noticing
  (section 8).
- **Configuration once per agent identity.** `tandemlog-cli init --workspace
  <folder> --name "Vex"` creates that agent's private profile in a platform data
  directory and records the folder. `TANDEMLOG_CLI_PROFILE` selects the profile;
  each additional agent gets a distinct profile, installation UUID and log, even
  on the same host. Exact default paths and profile selection are implementation
  questions (section 9). The host name may be descriptive, not the identity key.
  Never copy one live identity/profile to concurrent hosts; a separate concurrent
  writer needs a distinct installation. There is no fixed limit on agents.
  After setup, commands need no workspace flags. Windows MCP clients launch the
  installed `tandemlog-cli.exe` with `["mcp"]`; Flatpak clients launch `flatpak`
  with `["run","--command=tandemlog-cli","com.reddraggone9.tandemlog","mcp"]`.
- **No idle work.** CLI processes exit after each command. The MCP server opens
  the workspace on the first call, refreshes before each call (the stores already
  admit arriving peer bytes in the fresh-input callback), and closes the workspace
  after 60 s idle. It runs no timers while the workspace is closed.
- **Time and people.** Dates render the way the app shows them, in the host's
  zone (`--tz` overrides). Capture needs an assignee, as in the app, because the
  app uses its active user: `--for Lee|Hester`, defaulting to the profile's person
  setting if one is set. Attribution stays with the installation.

## 5. Read interface

Commands: `context`, `tasks list|search|show`, `food list|search|show`,
`products list|show|search`, `purchases list`, `history <id>` (operations on one
entity, with writer names), and `verify` (the Settings integrity audit, read-only).

- **Same semantics as the app.** Task views use `projectTaskView` and the app's
  filters (assignee, Open/Completed, upcoming, tags). Search covers titles and
  notes, ignores filters, and puts completed matches last. Food views are
  Stock/Retained/Deleted with the Inbox and Running low partitions; filters
  combine with OR within a field and AND across fields; search includes Deleted
  last. Rows are the app's groups: a Food row is a product with the same expiry,
  retention and location, with a count and its container IDs.
- **`context`** gives the agent its vocabulary in one small call: people, tags,
  locations, brands, counts per view, Running low, writer names, and versions.
- **Stable IDs.** JSON carries full UUIDs. Text output shows 8-character
  prefixes, and input accepts any unique prefix of 8 or more characters;
  ambiguity is an error, never a guess. Each entity also carries `rev`, a short
  hash of its admitted operation set, for preconditions (section 6).
- **Bounded output.** Default `--limit 50`, an opaque `--cursor`, `total`
  always, and a 32 KB output cap with an explicit `truncated` marker. Notes and
  long fields are truncated in lists (`show` returns them whole). `--format
  jsonl` streams everything without the cap, for scripts and analysis.
- **Example (text):**
  `3f9a1c20 Pay water bill · Due Oct 30 · ↻ monthly · @Lee #bills · rev 7c1e`
  and `9b2d40aa Milk · Great Value · 1 gal ×2 · exp Nov 3 · Fridge`. The first
  line states the view, filters and count; the last line gives `next:` when more
  rows exist.
- **Reads never write.** `init` is the only command that joins the workspace (one
  standalone installation record). `WorkspaceSession` needs a read-only open
  mode (new): reads skip open-time maintenance writes such as the occurrence-date
  migration, and the next write performs them, as the app's open would.

## 6. Write interface

**Coverage: every user-facing action.**
- Tasks: capture (multi-line), edit (title, notes, Start/Due with optional time
  and zone, This occurrence, Repeat, tags, assignee), complete, reopen, delete,
  move/reorder (same-date rule), bulk edit (schedule/assignee/tag deltas), bulk
  delete, and checklist add/edit/check/uncheck/delete/reorder.
- Food: add (count; expiry required as in the app, or `--inbox`), add another,
  edit (expiry, location, retention reason; name/brand/size edit the product, with
  the same "Also changes N other containers" scope report), remove one/remove,
  restore, move some (`food move-some <id> --count N --location L`, the row
  menu's Move some…), and bulk edit, including unify-by-rename. Products: set store link,
  set minimum (`products set <id> --link URL --min 2`), and `products merge <src>
  --into <dst> [--keep source|target]`.
- Undo (see below). Excluded: device-local settings (folder, appearance, device
  name).

**Same rules as the app.** Commands call the same store methods, so validation,
bulk-as-one-action, merge-on-rename and scope rules are identical. Field
validation errors come back per field (`{"field":"due","error":"Start must be on
or before Due"}`), matching the app's beside-the-field errors.

**Dry run and preconditions.**
- Every write accepts `--dry-run`. A dry run prints the exact typed effects
  (entities, fields before→after, merges, counts) and a `planHash`, and appends
  nothing.
- `--expect-plan <hash>` is **required for bulk actions, merges and imports** in
  both CLI and MCP commit calls. Dry runs can discover targets and supply the
  required revision map/plan hash without committing. Recompute under the write
  lock after fresh admission; reject
  a changed plan before appending. A dry run provides the hash, including exact
  target IDs, revisions and effects. A missing precondition is a validation error.
- **`rev` is required for every write changing an existing item**, not just
  complete/delete/merge. CLI uses `--if-rev <rev>` for one item; MCP requires
  `rev`. Multi-item writes carry an ID→revision map in the input/plan, including
  affected products, containers, checklist parents and ordering neighbors as
  applicable. Undo also supplies current revisions for its affected existing
  items. Create-only writes have no prior-item revision; creating something that
  also changes an existing item still requires that item's revision. Reject
  missing or stale revisions before any append. This prevents stale phone edits
  being overwritten and repeated completion advancing recurrence twice.
- Write output gives the action ID, affected IDs with their new `rev`, and the
  undo command.

**Retries.** Capture and Add accept `--request-id <uuid>`, and new entity IDs
derive from it. `createTasks` already treats a present ID as done, so a retried
capture after a timeout doesn't duplicate. Edits are set-to-value. Complete and
delete rely on `--if-rev`. A crash mid-append leaves an unterminated suffix that
the CLI's own next start compares and cleans, as the app does.

**Purchase import (Food products decision 7).** Receipt/itemization workflows
(including Vex's YNAB workflow) produce a plan, using the existing
`dryRunPurchaseImport` / `commitPurchaseImport` contract:
1. `purchases plan <lines.json>` takes loose lines (date, store, amount,
   currency, quantity, and either a product ID or name/brand/size/link), fills in
   `space`, `importId` and `sourceSha256`, and writes the canonical immutable plan
   v1. For lines without a product ID, it lists likely existing products, so the
   agent links "GV Whole Milk 1 gal" to the existing Milk product instead of
   minting a near-duplicate.
2. `purchases import plan.json --dry-run` gives the per-line report: product,
   purchase new or present, hand entries matched, Inbox containers to create.
3. `purchases import plan.json --expect-plan <hash>` commits one action with
   `food.purchase-import` provenance.

Idempotency uses a **generic source key `{kind, key}`**, with a stable provider
namespace and opaque per-line key. For example, a YNAB adapter may emit
`{kind:"ynab", key:"<transaction id>#<stable receipt-line id>"}`; other receipt
sources use their own kind and key without changing the interface. Line identity
must survive reordering/re-itemization, rather than being recomputed from mutable
values. A purchase is one line, not one transaction. Changed values under the
same source identity fail the dry run instead of duplicating. Retrying after an
Undo is a no-op, as designed.

**Undo: only `undo <actionId>`.** Retract one whole earlier action by this
agent installation, with current item revisions as above. Bulk edits and imports
undo as one unit across process restarts and preserve independent later
contributions (ADR0018 semantics). No partial field Undo, MCP per-session text
Undo stack, compensating text-revert option or snapshot overwrite is exposed.
Repeated Undo is an explicit already-undone/no-op result, not another retraction.

Whole-action Undo includes title/notes contributions when present. **This is a
required interface outcome, not functionality the current stores already
provide.** Native text Undo currently needs retained editor ownership and stack
order. Implementation must prove durable action-to-operation ownership and safe
selective text retraction across short-lived CLI processes using supported
mechanisms. It must preflight the entire action and append nothing if any part
cannot be undone (`undo_unavailable`), rather than silently undoing only non-text
fields. This limitation blocks claiming full action parity until resolved; it
must not be hidden by keeping an MCP session alive (section 9).

The agent cannot undo another writer's actions (Food already enforces same-writer
retraction; apply the same restriction to Tasks). The GUI's session toolbar Undo
does not gain ownership of agent actions. People can edit them or ask the agent
to undo them; browsable cross-writer audit/Undo remains outside this release.

## 7. Concurrency, versions, packaging

- **Same machine as a GUI.** Each has its own profile and installation, so there
  is no shared lock. Each appends only to its own `.applog`, and each sees the
  other's writes through ordinary admission (the GUI's folder watcher picks them
  up within the debounce or the 15 s fallback poll). Sharing a package does not
  share the writer identity: independent processes sharing one log could race its
  own-writer append sequence/hash-chain head and private recovery state; a lock
  alone would not supply native text-actor/Undo ownership. Use the existing text
  actor allocation rules per installation and editing allocation, never a cloned
  actor or GUI session. Profile locks serialize same-identity calls while
  distinct identities admit each other's writes normally.
- **Same agent profile.** `ProfileLock` is exclusive and non-blocking. The CLI
  retries for up to `--wait 30s` (agents run calls in parallel), then exits with
  `profile_in_use`. A CLI must never point at a GUI's profile.
- **Versions.** The CLI is built and released with the app. It reads with the
  current decoders, so newer history (an unknown family or revision) stops it with
  exit code 3 / `update_required` and no write, exactly like the app. Its private
  profile follows the app's rules: no downgrade, and future schemas fail closed.
  The CLI's own output is versioned separately (`"v":1`). Within v1 it changes
  additively; renames and removals bump it.
- **Errors.** Stable JSON error kinds and exit codes: `not_found`, `ambiguous_id`,
  `validation`, `stale`, `plan_changed`, `update_required`, `profile_in_use`,
  `history_damaged`, `undo_unavailable`, `write_pending` (retry the same command).
- **Packaging (accepted).**
  - Linux: GUI and headless executable in the **same existing Flatpak**.
    Invoke `flatpak run --command=tandemlog-cli com.reddraggone9.tandemlog` with
    CLI arguments appended. The default app command still opens the GUI.
    Package sqlite3 and the text engine for both entry points; do not require
    GTK/display initialization for CLI calls.
  - Windows: `tandemlog-cli.exe` inside **both the existing installer and ZIP**,
    alongside its native libraries, with the same release version as the GUI.
  - **No additional tarball, download, package or independently updated CLI.**
    Android has no CLI entry point.
- **Install on Farnsworth.** Install/update the ordinary Flatpak once, run its
  second command headlessly, select Vex's private profile and `init` it against
  the synced workspace. This does not initialize or reuse a GUI profile. Verify
  sandbox workspace access and native-library loading during implementation;
  neither requires a separate archive or a running GUI. Updates deliver both
  executables together; newer unsupported history still fails closed.

## 8. Testing and the performance gate

- **Parity test.** A test enumerates the app's user-facing action set (store
  command entry points used by the UI) and fails if any lacks a registry command.
  This keeps "every user-facing write" true as the app grows.
- **Golden outputs.** Text and JSON for list, search, show and context on the
  synthetic fixtures (including `test/fixtures/food-products/`), with limits,
  cursors and truncation.
- **Process tests.** These run the built executable against temporary
  workspaces:
  - The CLI and a second installation (a stand-in for a GUI) write
    concurrently, and each sees the other's writes.
  - `--dry-run` appends no bytes; all existing-item writes reject missing/stale
    revisions; bulk/merge/import reject missing or changed plan hashes.
  - Request-ID retry doesn't duplicate.
  - Whole-action Undo (including mixed text/non-text) works across a restart,
    preserves peer contributions and repeated Undo is a no-op. An unavailable
    text retraction refuses the whole action with unchanged canonical bytes.
  - Several agent identities on one host use distinct profiles/logs; same-profile
    parallel calls serialize or fail without chain/text-actor collisions.
  - A newer-format fixture gives `update_required` with unchanged bytes.
  - A crash mid-append recovers.
  - Reads leave the workspace and the profile byte-identical.
  - An MCP `initialize` / `tools/list` / `tools/call` smoke test.
- **Future CI/native acceptance.** Build and smoke-test on hosted Linux and
  Windows runners (mandatory correctness). Exercise the packaged Flatpak second
  command without a display, Windows installer and ZIP, per-agent profile
  selection, sandbox workspace access and native-library loading. These are
  future implementation gates; no CI or benchmarks run for this design change.
- **Performance.** The CLI reuses already-budgeted store paths. The
  `WorkspaceSession` extraction changes the app's open/command path, so the RC
  gets the normal reference qualification under unchanged budgets. Before
  implementation acceptance, register new CLI/MCP actions and intended
  responsiveness budgets under the existing performance coverage contract.
  Cold-open+list and purchase-import apply need measurement coverage; whether
  additional CLI-specific timings are advisory or mandatory is an implementation
  gate question, not permission to waive existing budgets.

## 9. Settled requirements and implementation questions

**Settled (Lee's accepted direction, 2026-10-28):** separate headless Dart
`tandemlog-cli`, CLI and stdio MCP using shared domain commands, shipped together
with the GUI in Flatpak/Windows installer/Windows ZIP; no extra download. One
installation/private profile/log per agent identity, not per host, without an
agent-count cap or GUI log sharing. Whole-action `undo <actionId>` only; required
revisions for every existing-item mutation; required plan hashes for
bulk/merge/import; generic `{kind, key}` source identity. Implement on a separate
release line only after Food products is stable, not during RC.2 qualification.

**Implementation questions to resolve on that later line (not requests to
re-approve the direction):**

1. Prove the pinned Dart/native-assets build and library path injection on both
   platforms, including headless Flatpak launch and sandbox folder access.
2. Choose per-agent profile paths/selection in Flatpak and Windows, with explicit
   isolation from the GUI, no accidental identity cloning and profile locks.
3. Extract shared workspace sequencing/read-only open without changing GUI
   semantics. Determine how private disposable caches can refresh while reads
   keep durable workspace/profile state unchanged; qualify changed hot paths.
4. Prove whole-action text Undo across process restarts and after intervening
   peer edits, including crash-safe all-or-nothing preflight. Current native
   session-bound Undo is insufficient. If this cannot be achieved under the
   existing canonical semantics, stop and record the blocker: do not weaken Undo,
   fabricate a compensation or introduce a format change under this acceptance.
   Any necessary durable-format change needs its own compatibility design and
   explicit decision under the one-release format rule.
5. Finalize canonical revision/plan hashing, multi-item dependency scope, action
   receipt persistence and retry behavior (including already-undone actions).
   Admission plus validation must be serialized with the append; peer arrivals
   after that boundary remain ordinary concurrent contributions, not a promise
   of distributed locking.
6. Set CLI-specific timing coverage/budgets under the performance contract before
   accepting implementation. Existing mandatory GUI/store budgets stay intact.

Rejected alternatives: an HTTP server inside the GUI (running app and network
access/auth needed); a Python canonical writer (duplicates semantics and violates
no-direct-writers); a headless Flutter mode (unneeded GUI dependency); shared
GUI/agent writer state (chain/recovery/text ownership coupling); and a separate
Linux tarball (extra installation/update path). Revisit only if implementation
evidence invalidates the accepted approach, documenting the tradeoff first.

## 10. Not in scope

Notifications or background alerts (Running low stays in the app; Vex can run
`products list --running-low` on its own schedule); a network API; signing agent
writes; settings changes; any canonical format change.

## 11. Implementation (2026-10-29)

Code: `lib/agent/` (registry, CLI, MCP, commands), `bin/tandemlog_cli.dart`,
`lib/application/workspace_session.dart` (the app's open sequence, now shared),
`lib/food/food_rows.dart`, `lib/platform/host_zone.dart`, `tool/build_agent_cli.py`.

**Section 9 answers.**
1. *Build and packaging.* `dart build cli` with the pinned SDK; the tool lays out
   `bin/tandemlog-cli[.exe]` beside `lib/` (SQLite native asset plus the app's own
   text library, copied byte-for-byte) and loads the text library by explicit
   path. Flatpak: `/app/tandemlog-cli`, command `tandemlog-cli`. Windows: `cli\`
   inside the Release bundle, so the installer and ZIP carry it unchanged.
   The hosted CI workflow is *configured* to build and smoke it headlessly on
   both platforms and from the installed packages, including one Windows call
   without `--tz` and a Flatpak call against a host folder granted with
   `flatpak override --filesystem`; it has not run on this release line yet,
   so packaged Windows/Flatpak launch remains unverified. Windows reads the
   zone through `GetDynamicTimeZoneInformation` and the system ICU, as the app
   runner does.
2. *Profiles.* `TANDEMLOG_CLI_PROFILE` (or `--profile`) names a profile under
   `<XDG_DATA_HOME>/com.reddraggone9.tandemlog-agents/` (Flatpak: the app's
   sandbox data directory; Windows: `%APPDATA%\com.reddraggone9\tandemlog-agents`)
   or gives a path; default `default`. `TANDEMLOG_PROFILE` is never read. A
   profile is accepted only with its agent marker file, so the CLI cannot
   open an app profile. `init` holds the identity lock throughout and refuses a
   non-empty directory, so concurrent inits of one profile yield exactly one
   identity; if it fails before its join is written it removes only the files
   it created, and once joined the profile is kept.
   An OS lock (`agent.lock`) serializes one identity; `--wait` (default 30 s).
3. *Read-only open.* Reads copy the private profile to a temporary directory
   under the identity lock and open the workspace through a folder that refuses
   every write; anything that would need to write fails as `write_pending`.
   Reads leave the workspace and the profile byte-identical (tested). Reads skip
   shared-text initialization and the occurrence migration; the next write runs
   them, as the app's open does. Refused writes leave canonical bytes unchanged;
   the agent's own disposable caches may refresh.
4. *Text Undo.* As proven: one deterministic Undo allocation per agent writer
   and field context; the native document is rebuilt from the canonical lineage
   with own edits as owned receipts, peer packets as remote updates and own
   earlier Undos regenerated and byte-compared. The compensation is one
   `task.textEditUndone`. Inherited (recurring-successor) multi-context lineages
   and creations are refused whole as `undo_unavailable`. Tested across fresh
   opens with another agent's concurrent edit.
5. *Revisions and plans.* A task's or checklist item's `rev` hashes its sorted
   admitted event IDs. Food revisions hash projected state: a container's
   projection; a product's name, brand, size, links and minimum; a merged-away
   product's alias and root; a purchase's values. This is a recorded deviation
   from the feasibility note (see below). Each write checks the revisions
   before it starts and again inside the store's serialized append, after fresh
   admission (`canCommit` on Task `complete`/`reopen`/`command`/bulk/move,
   `addChecklistItem` (parent and anchor), Task and Food `undoOperations`, and
   Food `remove`/`restore`/`changeDetails`). A dry run executes the command
   against a copy of the profile and a copy-on-write view of the workspace and
   reports the effects: changed fields, task moves (with the task each now
   precedes), product changes including merges (`mergedInto`), and purchases.
   `planHash` binds command, arguments and effects without clock readings; purchase imports also bind exact plan-file bytes, read once for the preview and commit.
   Bulk edit/move/delete, multi-container Food edit/remove/restore,
   product-changing Food edits, merges and purchase imports re-run the dry run
   under the held identity lock and commit only on a matching `--expect-plan`.
   The commit then appends only while the workspace still has exactly the
   observed state the plan was computed from (tasks, order, containers,
   products, purchases, manifest, writer and canonical history heads), checked again inside the append; any change in
   between gives `plan_changed` and a retry re-plans. Undo takes `--rev` for
   every task, checklist item, container, product and purchase the action
   changed (`none` for a target that no longer exists); each write result
   prints the complete Undo command with current revisions.
6. *Performance.* Registered (merged from `vex/agent-perf-coverage-20261029`):
   eight `agent.*` labels with budgets declared before measurement — reads
   400ms median/600ms maximum, single writes and whole-action Undo 500/750,
   dry runs and the two-line purchase import 700/1000 — on all three shapes,
   with startup-class growth rules
   ([performance gate](performance-gate.md#agent-cli-prospective-coverage-2026-10-29)).
   After the fixes recorded there, every label meets its budget on dense-1
   and dense-2; on dense-food single writes (complete, text edit, its Undo)
   miss their 500ms median by 3–17ms and the planned purchase import its
   700ms median by about 100ms (warm history open plus close-time seal; the
   import opens twice). The ~300-writer refresh case from the writer-cap review
   is not registered yet. The `WorkspaceSession` change to the app's open
   path and these storage changes still owe the normal reference
   qualification.

**Differences from sections 4–7.**
- MCP opens the workspace for each tool call and closes it, instead of keeping
  it open for 60 s: simpler, no idle work, peer arrivals admitted per call.
- `tasks bulk-move`, `people add` and `products search` exist in addition to the
  listed commands; device name stays a device setting (`init --name`).
- `food move-some` names the row by any of its containers (`--if-rev` of that
  container) and moves the row's first `--count` current containers, as the
  page does at Move time. It always needs `--expect-plan`, because the command
  rather than the agent picks the containers; the dry run lists them. One
  Location `changeDetails`, one action, one Undo.
- Undo of a creation is refused; delete the item instead. Undo of an Undo is
  refused (`undo_unavailable`); repeat the change instead. Neither is
  advertised in write results.
- `purchases import` follows the general plan contract: its dry run runs on the
  copy-on-write view, a missing `--expect-plan` is `validation`, and `planHash`
  binds the import's effects (the plan file's own hash is `importPlanHash`).
  `purchases plan` never overwrites a file without `--force` and never writes
  inside the workspace folder.
- Food revisions are projected-state hashes, not admitted operation IDs (the
  feasibility note asked for operation IDs). Consequence: a change that
  restores an identical projected state keeps the old rev (ABA), so a write
  holding that rev proceeds. Tasks and checklist items use operation IDs.
- Output is capped at 32 KB of UTF-8 in text, JSON and MCP; dropped rows are
  reported (`truncated`, `shown`) and `next` resumes at the first dropped row.
- A partial `tasks bulk-edit` (some batches committed) returns its actions with
  `partial: true` and the failure, and exits with that failure's code.
- MCP marks deletes, removes and merges `destructiveHint`; malformed JSON-RPC
  messages (batches, non-object params) get errors and the server keeps going.
  Unexpected failures use kind `internal` (exit 2), outside the section 7 list.
- `init --person` sets the default assignee; captures otherwise need `--for`.
- Exit codes: 2 validation/undo_unavailable/other, 3 update_required,
  4 profile_in_use, 5 history_damaged, 6 stale/plan_changed, 7 write_pending
  (also a peer's write arriving mid-command: retry the same command),
  8 not_found/ambiguous_id.
- The registry is checked against the app's store calls by
  `test/agent_parity_test.dart`.
- Count-only writer ceilings were removed (feasibility record); workspaces with
  more than 256 installations need every device on this release or newer.

