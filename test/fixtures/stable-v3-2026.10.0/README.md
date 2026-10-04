# First stable v3 compatibility history

Frozen synthetic history produced by the accepted RC38 application closure at
`c3c1bd87dc3495de6158e1913e1f3e1f8bdb6f2e`. It is representative application data,
not private imported data or migration metadata. Future stable readers must
preserve its canonical bytes and event meanings. Do not regenerate these files
from a newer writer/decoder to hide a compatibility failure.

Two writer streams contain all nine supported event types, exact decimal causal
clocks, Unicode distinctions, notes/links, observed tag removal, reassignment,
manual move/Undo, completion/Reopen, deletion, date/time precision and named
zones. Recurring completion proposals cover both an untouched retracted successor
and a successor retained because another writer edited it. Scheduled overrides
are cleared on the successor, while underlying due/start cadence remains.

`expected-rows.json` freezes the projected domain state and global order. The
regression ingests both stream arrival orders, verifies the full chains, reopens
the same SQLite cache, rebuilds with a fresh private profile and appends through
a fresh writer without changing either historical stream. The independently
generated `../event_chain_v3.jsonl` retains separate wire/hash golden coverage.

The fixture metadata is test-only and is never copied into an application
workspace. Canonical workspace files are only the manifest and writer JSONL logs.
