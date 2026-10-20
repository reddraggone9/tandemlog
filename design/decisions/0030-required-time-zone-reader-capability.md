# Required support for additional time zone names

Status: Accepted design, 2026-10-20; implementation and acceptance in progress.

## Context

The reviewed timezone0.11.2 package adds CST6CDT, EST5EDT, MST7MDT and PST8PDT.
Older applications reject those names. Its2026e database also changes effective
rules for existing names, so replacing the default database would reinterpret
unversioned durable schedules. Lee delegated a compatibility mechanism requiring
older readers to update before consuming unsupported data. Merely rejecting the
new names forever is an interim hold, not that requested outcome.

## Decision

Preserve exact immutable2025c tables for all341 released names, including UTC.
The four added names use separately fixed immutable2026e tables. No geographic
alias normalization or general existing-zone rule migration occurs.

Readyv4 workspaces can explicitly enable the four names in Settings. Confirmation
states that every device must update and that the shared change cannot be undone.
Later changes nothing. V3 uses the existing explicit workspace upgrade first.
An unsaved draft alone does not block this additive operation: workspace, epoch,
controllers, captures and baselines stay intact. Outstanding durable saves must
be resolved; every Save checks actual current workspace permission again.

Enabling adds one deterministic requiredCapabilities field to the existing
seven-key canonical v4 manifest. The descriptor fixes the feature version,
supported reader floor (build98), both reviewed data hashes and four names.
Only that exact supported extension is understood. Removing it must reproduce
the exact original canonical manifest. Unknown, malformed or future requirements
fail closed; normal manifest equality remains strict for every other change.

The two delivery-order barriers are independent. An old reader receiving the
manifest first reports that the app must update. If a new-name log arrives first,
its old schedule decoder rejects the unsupported name before admission. Current
readers additionally enforce workspace permission at physical and pending
admission, before native binding, durable intents, reservation and append.
A process-global parser vocabulary never grants workspace permission.

This is a reader floor, not remote writer revocation. An old in-flight or offline
writer can still append compatible records using existing2025c meanings. Those
bytes remain preserved and admissible. No global roster, ACK/freeze protocol,
snapshot frontier, new event, new epoch or canonical stream rewrite is needed.

## Protected transition and recovery

Use a separate typed protected_workspace_capabilities journal in the existing
local SQLite database. The journal binds exact old/target manifests, space,
unchanged epoch, profile writer/location, role, phase and retained initiator
consent. A deterministic target lets simultaneous enablers converge on the same
bytes. Settings Later creates no journal.

Only an initiator's own retained consent/replacing intent can authorize checked
manifest replacement and owned interrupted-prefix recovery. A peer/adopter
journal never authorizes file repair. Divergent or ambiguous provider bytes,
lost permissions and invalid journals preserve evidence and block. SAF checked
replacement is not a remote compare-and-swap or distributed lock. Once replacing
begins, recovery proceeds forward. Before replacing an observed partial target,
the initiator durably retains its exact byte-prefix length in the protected
journal. The fixed target bytes plus that length reconstruct every observed byte,
including an empty prefix or a partial UTF-8 sequence. Unique bounded evidence
survives completion and repeated interruptions. Journal failure or exhausted
evidence capacity leaves provider bytes untouched. Desktop recovery also retains
its existing interrupted temporary-file archives; Android checked replacement
uses this private evidence without creating another shared file.

A supported new manifest is prospective until full normal history admission
succeeds. Both initiating and adopting profiles promote the exact protected
manifest, complete the journal and stage both projections in the SAME successful
SQL transaction. Any validation, projection, SQL or COMMIT failure retains the
previous protected manifest and last good views; an earlier durable nonterminal
intent may remain. Existing own pending receipts must satisfy OLD permission
before adoption; activation cannot legitimize fabricated pre-feature intents.
Compatible pending bytes, observed heads, native authority and Undo remain exact.

Completed v3-upgrade receipts and an acknowledged peer's unfinished local
completion recognize only this same narrow extension of their original ready
manifest. Exact original source, output and acknowledgement proofs still apply;
their stored bytes and conversion/ACK schemas are not rewritten. Startup resumes only authorized owned replacement before
ordinary opening; normal shared-read retry stays read-only. Settings exposes a
separate owned Resume/restore-access path.

## Local profile compatibility

The new authority table requires the strict additive schema4-to-5 migration.
Opening build98 upgrades its LOCAL profile even before shared activation; older
RCs cannot reopen that schema5 profile. Other devices using their own schema4
profiles can still read the unchanged seven-key workspace until explicit
activation. Tests of old shared readers use preserved schema4 profiles so that
a database-version refusal is never substituted for manifest/alias proof.

A bound activated profile refuses a restored old seven-key manifest. A truly
fresh profile with every shared/private activation proof removed cannot know
that an activation once happened; it treats that restored input as legacy and
still rejects additional-name data. The UI provides no downgrade operation.

## Alternatives and consequences

A blanket database update changes old meanings. A global enable flag leaks
permission across workspaces. An unbounded manifest mismatch exception discards
protected authority. Reusing the v3 conversion session would invent inappropriate
seals/ACKs for a capability that changes no existing record. Nonces or shared proof
files create unnecessary competing targets. Optional schema4 authority-table
reconstruction would weaken the frozen-schema/missing-authority boundary.

Acceptance must cover genuine old readers in both delivery orders; direct,
bulk, native, recurring, checklist, import and retry admission; independent
workspaces/profiles; transactional adoption rollback; completed conversion
receipts; exact pending recovery; interrupted SAF writes; concurrent enabling;
and native Settings/draft workflows in both themes and enlarged text.
Existing shared-state tests or older artifact evidence do not accept this new
feature. Publication and production operations remain separately held.

Revisit when another required capability or a versioned existing-zone rules
update is concrete. Do not generalize a capability framework speculatively.
