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
- Full application analysis and format checks pass; the initial source passed64
  tooling policies. Final corrected hosted source passes all74 on Linux and the
  Windows suite with four platform skips; the local run retains its one skip.
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
earlier checkpoints and pending acceptance. The final source7ae now passes the
full signed candidate, exact original-artifact and actual installed Flatpak
catalog/private-profile gates; independent final-range notes/media review accepts
3d671 through7ae. [Final handoff](../candidate/build62/README.md) records all three
original archives and the signed APK. Parent exact Android QA/Show taps and fresh
private publication clearance remain required. No actual Bazaar GUI is inferred
from local composition or the successful hosted catalog-file validation.

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

## Portable catalog correction

Corrected source43df cleared actual Windows app units953+2skips and107 native
contracts, but two catalog-tool tests exposed backslash relative paths compared
against required forward-slash paths. The two report-path conversions now use
`as_posix()`. A real catalog/PureWindowsPath regression reproduces the exact RED
and all10 metadata tests pass after correction. Independent review repeated RED,
GREEN and actual five-icon composed-catalog comparison; Linux catalog JSON is
byte-equivalent. All74 local tooling checks execute:73 pass,1 existing platform
case skips. No skips/bypass, fixture or app-code changes are added. Both incomplete
prior attempts remain ineligible; a fresh complete candidate remains required.

## Final candidate closure

Source7ae/candidate38121211371 and pushCI38121201969 pass every hosted job.
Linux956 unit/129 native workflows/107 contracts/Rust4/74 tool checks and
Windows953 unit/two skips/107 contracts/Rust4/74 tool checks/four platform skips
pass. Both exact original installed desktop lifecycles pass. The earlier correction
paragraphs are historical checkpoints; their pending fresh-run requirement is now
fulfilled. The application remains byte-identical to the final4310708 local-tested
source. [Original14-member manifest](../candidate/build62/artifacts/manifest.json)
and [native handoff](../candidate/build62/README.md) record identity and explicit
remaining Android/publication gates. No RC2 publication or stable promotion.

The [exact handoff](../candidate/build62/README.md) qualifies supplemental Android RELRO
static guidance: affected libraries are byte-identical in stable56, RC1/60 and62;
no runtime failure is established. Parent disposition is pending before publication,
while exact Android UI QA may proceed. No new gate or toolchain upgrade was added.
