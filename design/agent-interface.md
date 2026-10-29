# Agent interface (proposal)

Status: **Proposed, not accepted.** This is a design only. Nothing here is
implemented. Target: the first release after Food products reaches stable.
Section 9 lists the decisions Lee still has to make.

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

## 2. Recommendation in one paragraph

Ship one headless Dart executable, `tandemlog-cli`, built from the same source and
version as the app. It links the app's pure-Dart domain/storage/Food code and the
same native text engine, but not Flutter. Every command has terse text output and
compact JSON output. `tandemlog-cli mcp` serves the same command registry as MCP
tools over stdio. There is no network listener and no auth. The CLI is its own
installation, with its own private profile, attached to the device's synced
workspace folder like any other device. Its writes are ordinary actions attributed
to that installation. **It needs no canonical format change**, so it adds no
upgrade step for the other devices.

## 3. What the code says (where the starting proposal changes)

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
   only with exclusive ownership forever. A fresh installation is cleaner.
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
- **Configuration once.** `tandemlog-cli init --workspace <folder> --name "Vex
  (Farnsworth)"` creates the profile in the platform data directory
  (`$XDG_DATA_HOME/tandemlog-cli`, `%APPDATA%\Tandemlog CLI`) and records the
  folder. After that, commands need no flags. `TANDEMLOG_CLI_PROFILE` overrides
  the profile location. The MCP client configuration is
  `{"command":"tandemlog-cli","args":["mcp"]}`.
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
  restore, and bulk edit, including unify-by-rename. Products: set store link,
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
- `--expect-plan <hash>` applies only if recomputing the plan yields the same hash.
  Use it for anything previewed: bulk edits, merges and imports.
- `--if-rev <rev>` on single-entity writes refuses with `stale` when the entity
  changed since the agent read it, for example a phone edit arriving through sync.
  The MCP schemas make `rev` required for complete, delete and merge, which are
  the actions where acting twice or on stale data does damage (completing a
  recurring task twice advances it twice).
- Write output gives the action ID, affected IDs with their new `rev`, and the
  undo command.

**Retries.** Capture and Add accept `--request-id <uuid>`, and new entity IDs
derive from it. `createTasks` already treats a present ID as done, so a retried
capture after a timeout doesn't duplicate. Edits are set-to-value. Complete and
delete rely on `--if-rev`. A crash mid-append leaves an unterminated suffix that
the CLI's own next start compares and cleans, as the app does.

**Purchase import (Food products decision 7).** This is Vex's YNAB itemization
workflow producing a plan, using the existing `dryRunPurchaseImport` /
`commitPurchaseImport` contract:
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

Idempotency is per receipt line: `source = {kind:"ynab", key:"<YNAB transaction
id>#<receipt line n>"}`. A YNAB transaction is one receipt, but a purchase is one
line. A re-itemization that changes a line's values fails the dry run instead of
duplicating. Retrying after an Undo is a no-op, as designed.

**Undo.** `undo <actionId>` retracts one whole earlier action by this
installation, through the store-level retraction. Bulk edits and imports undo as
one unit, survive process restarts, and keep independent later contributions
(ADR0018 semantics). Two limits:
- *Title/notes text.* Native text Undo is session-bound. The MCP server keeps a
  per-session stack, so text edits made earlier in the same session can be undone
  natively. Otherwise `undo` reports the text part as not undoable, and
  `--revert-text` writes a compensating text edit only if the current text still
  equals what the agent wrote.
- *Other writers.* The agent cannot undo actions made by people's devices (Food
  enforces same-writer retraction; the CLI applies the same rule to Tasks). The
  app's toolbar Undo is per session, so Lee and Hester cannot toolbar-Undo an
  agent write. They can edit it back or ask Vex.

## 7. Concurrency, versions, packaging

- **Same machine as a GUI.** Each has its own profile and installation, so there
  is no shared lock. Each appends only to its own `.applog`, and each sees the
  other's writes through ordinary admission (the GUI's folder watcher picks them
  up within the debounce or the 15 s fallback poll).
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
  `history_damaged`, `write_pending` (retry the same command).
- **Packaging.**
  - Linux: `tandemlog-cli-<version>-linux-x64.tar.gz` (executable plus `lib/`
    with sqlite3 and the text engine) and its checksum, attached to each release
    before publishing, as the portable ZIP is.
  - Windows: `tandemlog-cli.exe` inside the existing portable ZIP and installer,
    next to `tandemlog_text.dll`.
  - Android: none.
  - The Flatpak is left out initially (`flatpak run --command` adds friction and
    no host needs it).
- **Install on Farnsworth.** Vex downloads the tarball with `gh release
  download`, verifies its SHA256, unpacks it into
  `~/.local/opt/tandemlog-cli/<version>/`, points `~/.local/bin/tandemlog-cli` at
  it, and runs `init` once. Each app update includes a CLI update, and the CLI
  refuses newer data until then.

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
  - `--dry-run` appends no bytes; `--if-rev` and `--expect-plan` refuse stale
    state.
  - Request-ID retry doesn't duplicate.
  - Undo works across a restart.
  - A newer-format fixture gives `update_required` with unchanged bytes.
  - A crash mid-append recovers.
  - Reads leave the workspace and the profile byte-identical.
  - An MCP `initialize` / `tools/list` / `tools/call` smoke test.
- **CI.** Build and smoke-test on the hosted Linux and Windows runners (mandatory
  correctness).
- **Performance.** The CLI reuses already-budgeted store paths. The
  `WorkspaceSession` extraction changes the app's open/command path, so the RC
  gets the normal reference qualification under unchanged budgets. Proposed (D7):
  record CLI cold-open+list and purchase-import apply timings as advisory, not
  new mandatory budgets.

## 9. Open decisions for Lee

Each has a recommendation.

1. **Identity on Farnsworth.** **Rec: a new installation "Vex (Farnsworth)"** with
   its own profile under Vex's account. Don't reuse e52144b5 (section 3.4). Cost:
   a sixth permanent writer file.
2. **Agents on other machines.** **Rec: allowed when useful, one installation per
   machine, named "<agent> (<host>)"**, never sharing a GUI profile. Only
   Farnsworth gets one now.
3. **CLI plus MCP in one binary.** **Rec: yes.** The CLI needs no configuration
   for any agent with a shell, and MCP is a thin adapter for agents without one.
   Alternatives rejected:
   - Localhost HTTP inside the GUI: needs the app running, plus auth, and doesn't
     fit serverless sync.
   - A Python reader/writer: duplicates semantics and the CRDT text code, and
     violates the no-direct-writers rule.
   - A headless mode in the Flutter binary: GTK isn't installed on Farnsworth.
4. **Undo of agent writes from the app.** **Rec: not now.** Vex undoes on request,
   and people can edit back. Revisit with the "browsable audit history" idea.
5. **Required preconditions.** **Rec:** `rev` required (in MCP schemas) only for
   complete, delete and merge; optional elsewhere; dry run optional except where
   the agent's own policy asks for it (Vex: bulk, merge, import).
6. **Packaging.** **Rec:** a Linux tarball plus the CLI inside the Windows ZIP and
   installer; no Flatpak or Android CLI.
7. **Performance gate.** **Rec:** correctness tests mandatory; CLI timings
   advisory; the refactor qualifies under the existing budgets.
8. **Purchase source key.** **Rec:** `ynab:<transaction id>#<receipt line>`, so
   idempotency is per receipt line, not per transaction.
9. **Name.** **Rec:** `tandemlog-cli` (avoids clashing with the app's executable
   on Windows).

## 10. Not in scope

Notifications or background alerts (Running low stays in the app; Vex can run
`products list --running-low` on its own schedule); a network API; signing agent
writes; settings changes; any canonical format change.
