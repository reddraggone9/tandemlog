# ADR 0028: App-owned shared workspace upgrade

Status: implementation approved by Lee on 2026-10-18; implementation and synthetic
acceptance in progress. Production conversion and stable publication have not
been authorized for this engineering task.

## Problem and decision

RC.2 reads and writes unified v4 history but leaves activation to a synthetic
engineering helper. That misses the intended app-owned migration experience.
Offer an upgrade for an existing v3 folder in the app, with explicit initiating
confirmation, a confirmed roster of participating installations, and one Join
confirmation on each peer. The app performs and verifies backup, conversion and
activation; users do not run an external converter.

Keep the Settings entry available. Hide the optional in-page offer while the
on-screen keyboard is visible, then restore it when the keyboard closes. This
leaves room for retained diagnostics during narrow, enlarged-text editor close
transitions without changing draft guards or upgrade consent.

This supersedes ADR0027's synthetic-only runtime activation boundary. The
synthetic helper remains restricted to its owned temporary directories.
Implementation and release acceptance continue to use isolated synthetic data.

## Coordination and identity

Historical installation owners and active participants are different sets.
Retain every original writer, semantic identity, clock, hash, Undo reference and
native text lineage. A new participant need not own any historical stream.
Task writer IDs and verified deterministic Food mappings identify owners;
Food-only owner IDs cannot be recovered by reversing their UUID derivation.
Missing mappings block preparation until an original installation identity or
trusted backup supplies the mapping. Device labels never prove ownership.

One explicitly selected initiating device coordinates. Every participating app
must implement upgrade protocol1, settle earlier saves, consent and persist its
own freeze in its existing local.sqlite profile. It validates the same source
and staged-output digests before writing its own acknowledgement. No synthetic
profile, initiator loop or copied writer identity may acknowledge another device.
Shared receipts are cooperative client attestations, not authenticated discovery
or proof that unseen/offline clients have stopped. Conflicting proposals and
duplicate provider files fail closed; folder sync supplies no distributed lock.

Finish drafts and pending saves on every active device before Begin. A draft
found on a peer after preparation starts is preserved; saving it requires the
initiator to cancel before staging, then prepare a new snapshot. An excluded
older client must remain stopped. Removing an installation from the active roster
does not delete, merge, adopt or transfer its historical writer.

## Durable boundaries and recovery

Take the source snapshot and persist freeze on the actual profile queue after
already-admitted work drains. Task/Food command admission also checks the local
freeze before durable receipt/native binding. Shared session and orphan upgrade
artifacts block new v3 writes even before that installation joins. Only exact
previously protected save receipts may finish through the recovery action; any
resulting source change invalidates the sealed snapshot.

Keep exact original manifest and source bytes, conversion recipe, operation
intents and progress in protected_app_migrations. Use no new permanent local
database, reset identity or replacement profile. Retain the sealed original v3
files; automatic source deletion is outside this release. Shared session/receipt
files are bounded, versioned and tied to one coordinator, roster and snapshot.
A source change invalidates old acknowledgements rather than silently resealing.

Before staging, the initiating device can cancel without changing canonical
history; each peer validates cancellation before releasing its own freeze.
Once staging begins, recover forward. Journal exact expected/replacement bytes
before manifest mutation, verify provider readback, and repair only an intended
prefix proven by that installation's retained intent. Divergent bytes and unknown
temporary documents remain preserved and block. Never reconstruct trusted
authority by discarding caches or generating a new writer.

Publishing ready=true is irreversible. A peer can append immediately afterward,
so recovery validates the sealed conversion prefix and valid v4 descendants
rather than demanding equality to the original whole output file. Each profile
finishes only after actual validation; normal runtime retains its existing common
history fences. Late v3 writes pause both sections and preserve the ready history;
automatic reconciliation of those late edits is not part of this upgrade.
The initiating installation and its protected profile must remain available to
resume an interrupted staged upgrade.

## Android and rehearsal

Use the existing SAF tree grant and document identities. Capability checks,
bounded expected-byte replacement, explicit truncation/sync and exact readback
do not constitute an atomic operation across providers or a global lock.
After confirmation, an owned probe verifies required provider operations before
target mutation. Unsupported providers, grant loss and partial replacement
remain visible, recoverable errors. No broad storage permission is added.

A nested rehearsal copy must be a quiescent, complete, hash-verified snapshot.
Parent workspace discovery is nonrecursive; the sync service may still copy
nested directories. Keep original workspace and historical IDs, use a fresh
private installation/profile, and start a new upgrade session. Changing folder
selection alone does not isolate protected writer authority. Copying an entire
session/receipt tree is not cryptographic proof of where those bytes originated.
No trial writes or converted files are copied back into production.

The existing local schema3-to4 downgrade limitation remains: stable/build85 and
RC.1/build86 cannot reopen the upgraded local profile. App upgrade and shared
workspace format upgrade are separate operations.

## Warning readability on narrow screens

The upgrade dialog scrolls its title and body together while keeping actions
reachable. Actual Android320dp/200% text testing showed that a fixed large title
could leave less than one warning line visible. Sharing the viewport preserves
the requested font size and complete warning text; shrinking the type or hiding
the compatibility warning would weaken the decision the user is making.

Installation-ID labels and helper paragraphs wrap without a line cap. Keep labels
above the fields so enlarged text cannot be ellipsized by a single-line floating
label. In particular, the distinction that historical IDs preserve ownership
without adding participating devices must remain readable when expanded.

## Validation and revisit

Require real independent synthetic profiles, native desktop and Android SAF,
both themes and larger text, interrupted initial/staged/ready writes, delayed
and reordered files, unknown owners, pending saves, competing proposals, repeated
actions and immediate valid peer writes after activation. Compare legacy bytes,
Task/Food views, native text, settings and protected authority before/after.
Browser layouts and provider mocks are not native acceptance.

Revisit preparation-before-snapshot UX if coordinated draft finishing proves
burdensome. Lost-coordinator takeover, writer adoption, production rollout and
large-history performance expansion remain separate decisions.
