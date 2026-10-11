# Complete approved RC2/build62 scope

The initial three-change source00594c1 and cancelled build61 are historical
checkpoints. This batch adds default Task Search/toolbar Add, combined Food
Stock/Inbox and Filter/account parity, local-calendar expiration colors,
required manual expiration through the shared date control, a50-action Food
Undo stack, stable expanded-group anchors, and the independently reviewed
Flatpak catalog/private-XDG corrections. No publication, stable promotion,
live inventory import, profile reset or data migration occurs in this batch.

## Undo design and compatibility

[ADR0018](../../../design/decisions/0018-food-session-undo.md) records the accepted
decision. Only new Undo records use a closed Food v2 envelope/hash domain and
strictly earlier same-writer operation reference. Original Food operations keep
v1 serialization, writer/genesis, IDs, clocks, hashes and meanings; Task v3 and
the shared manifest are unchanged. Replay validates original references and
creation bases before filtering withdrawn contributions. Newer peer field edits,
contents alternatives and unrelated delete/restore tokens survive. Undo Add
hides untouched identities from active and Deleted without removing their
canonical births; later direct work protects the seed.

Immutable receipts form one session action only after full admission. A partial
original or inverse retains its exact protected packet and retries the same IDs
and bytes; Undo pops only after all inverses are admitted. Search, Filter, section
and user changes preserve history; accepted workspace changes clear it. Task
completion notices/callbacks cannot write from Food.

Actual frozen build60 reader sources verify unchanged v1, explicit v2 rejection
and older-peer Food isolation while Tasks remain writable. Downgrading the same
profile with unresolved v2 protected receipts can stop shared workspace admission.
Exact bytes remain intact; reopen the current compatible reader to recover.
The independent core and host reviews accept this disclosed boundary.

## Source-qualified checks

- Final application unit run:956 pass,0 fail, including the closed native fixture
  changes and one-line Search padding correction. Final affected native aggregate:
  13 pass,0 fail. Both execute the final application inventory below.
- Full application analysis and format checks pass;64 tooling policies pass.
- Food Undo core:65 focused and72 expanded checks pass, including literal
  old-reader execution, invalid known refs and12.4MB replay budget.
- Independent session tests:5 native Undo flows pass, plus the later newer
  same-field peer-edit extension. Test source revisions remain explicitly bound
  in the fixture attribution addendum; a recording-only change is not claimed
  as the original executed fixture.
- Independent native account/Snackbar5 and Tasks input/retry5 pass. Earlier
  migrated Tasks31 remain attributed to their original source.
- Initial changed native run passed10/13. Stock's final whitespace check and two
  valid date-save checks exposed stale native editing connections in the fixtures.
  The failure log is preserved; actual field taps/reconnection and controller-value
  assertions fix the harness, without changing production code. Follow-up native
  Stock and required-date results are recorded with the final demo/runtime receipts. The final aggregate passes all13 checks.
- The actual desktop demo exposed a wide Search label wrap. A rendered-line RED
  regression and one-line explicit padding correction pass final native wide100%
  and200% checks; independent review confirms unchanged48px target/callbacks.
- Actual changed-flow screenshots cover native GTK, both themes, wide/narrow
  layouts and enlarged text. They establish Linux evidence, not Android or Windows
  GUI acceptance. Scoped widget captures may show a debug banner; production
  captures and release media use the production app with synthetic data.

Reviews and native test inventories distinguish application bytes, fixture bytes,
earlier checkpoints and pending acceptance. The exact original signed candidate,
installed Flatpak catalog/private-profile lifecycle, original artifacts, parent's
actual Android QA and final full-range editorial approval remain required before
publication. Bazaar's actual target UI is not inferred from local AppStream
composition alone.

## First hosted attempt and bounded corrections

Candidate38119736399/source`d38ec4e29ae63dd1ed0925093ae41f0514d38912`
failed Linux tool acquisition before Flutter setup: apt would downgrade XMLB and
remove runner fwupd, and refused. Windows ended with exactly one frozen-reader
provenance failure from LF-to-CRLF checkout;952 other tests passed with2 platform
skips. Android debug passed; owner signing was skipped. Partial archives are not
accepted candidates and are not reused.

The corrected adapter verifies/extracts the same six audited packages privately;
its child-only library environment loads the reviewed tool closure without host
installation, hooks, downgrade or removal. Eight new acquisition checks,12 retained
packaging and5 installer checks pass, with independently repeated real acquisition,
validation/composition and catalog verification. The scoped fixture attribute
preserves every released source length/hash and canonical packet, demonstrated by
a real autocrlf Git checkout RED/GREEN regression and independent released-blob
comparison. Original fixture bytes, hashes and assertions remain unchanged.

All73 tooling checks execute:72 pass and1 existing platform case skips. Application
Dart/native code, display version and shipped payload source are unchanged. Both
corrections have independent acceptance. The original source inventory remains
historical;`corrected-candidate-source-inventory.json` binds the correction. A fresh
complete hosted run, exact artifacts/installed lifecycles and Android acceptance
remain mandatory.
