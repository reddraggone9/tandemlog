# RC7 replacement candidate and bounded Android handoff

Replacement version2026.10.2-rc.7/build52 changes only the new native test's
paint-host/path coverage inequalities to use the existing0.01px geometry
tolerance and advances the build counter. Production UI and reviewed notes,
images and demo bytes are unchanged; screenshots/demo remain accurately
attributed to actual build51 debug source. Exact replacement source is`74afbe294065f462b742b4570d4095e690e54b04`
on main. [Replacement signed candidate37945597400](https://github.com/reddraggone9/tandemlog/actions/runs/37945597400)
and [pushCI37945597874](https://github.com/reddraggone9/tandemlog/actions/runs/37945597874)
are running that exact source; their full terminal results remain pending.

Candidate51 source`aaf06bd17beb109a89e97aff402595f5e7c49ae2`,
[signed candidate37942135402](https://github.com/reddraggone9/tandemlog/actions/runs/37942135402)
and [pushCI37942135365](https://github.com/reddraggone9/tandemlog/actions/runs/37942135365)
failed the full Linux native suite with86 passed and one failed. The new host
coverage assertion expected right>=134.3625030517578 but observed134.36249923706055,
a0.000003815px float-bound difference. All preceding app/contracts/policy gates,
Windows and Android debug passed. Linux release/Flatpak and owner-signed APK
were skipped, so no signed build51 is available for native acceptance.
[Exact failure group](build51-native-containment-red.log) is retained. Replacement
focused native checks pass1/0 in19s with clean analysis. [Independent correction review](independent-build52-correction-review.json)
accepts the bounded change; full replacement/artifact/native/publication gates
remain pending. A resolved-reference download of the old Windows archive
through current Library materialization returnedHTTP403; no local ZIP digest
verification is claimed.

[Implementation](../disclosure-layout/independent-compact-implementation-review-final.json),
[editorial](../rc7-editorial/independent-editorial-review.json),
[actual desktop demo](../disclosure-layout/independent-desktop-demo-review.json)
and [final source-range extension](independent-reviewed-range-extension.json)
are independently accepted. Build51's reviewed code/test/version hashes are unchanged between media source
9b6f18b and aaf06bd. Build52 retains production/ADR/other tests unchanged; the
bounded tolerance/version change is covered by its independent correction review. Notes images use immutable
9b6f18b URLs. Reviewed notes SHA256 is
`a4ec1b294c04acabfcf02c7a607c6ff225afdb6f02060eb74d878e501b6fc0a1`.

## Exact Android delta acceptance

Use only the successful candidate's owner-signed APK from its android-release
artifact, after obtaining/verifying actual bytes. Record archive and APK SHA256,
source/version/package, owner certificate, device/API, screen/text scale and
provider. Reuse unaffected signed RC6 coverage only with explicit attribution;
RC6 acceptance does not cover the new disclosure paint/target behavior. No live
synced user data may be used. Use a dedicated synthetic installation/profile and
its isolated shared folder; preserve earlier logs and workspaces.

On actual Android, inspect the requested narrow phone layout at normal and
200% text, with/without secondary text and expanded/collapsed. Desktop/narrow
Linux inspection is already source-bound above; no additional tablet matrix is
requested. Count bottom
clearance must match ordinary secondary text6px. Target height is approximately
28 logical pixels at normal text and grows with text (48 at200%), width at least
48. Parent-body and child/check/menu/reorder targets remain48px and disjoint;
no hidden48px region overlaps adjacent text or another control. The arrow retains
its visible title-column edge, count begins13px from that column, line gap2px,
and row edges/padding stay as accepted in RC6.

Hold/tap arrow and count and the target's lower corners. Actual pressed ink must
be a short centered rounded rectangle with equal8px horizontal paint margins,
2px vertical margins, an intact rounded left edge and even color across both
margins. The paint-only margin must not borrow a clickable region. Expanding or
collapsing must not select/complete the parent or activate the next/child row.
Check native keyboard activation where available and accessible button/expanded
labels. Busy disables activation and focus as before. Record an actual Android
Show-taps video and inspect representative frames; the supplied Linux demo does
not satisfy this Android gate. Keep this delta bounded; no additional optional
matrix, dependency upgrade, persistence migration or live-data test is implied.

## Remaining publication gates

Require terminal successful candidate/full hosted checks, exact accepted artifact
identity and native acceptance, independently reviewed notes/media, and a fresh
parent-supplied quota reading. Quota lookup is unavailable in this cloud worker;
no earlier reading is reused. Keep the reviewed trusted publication path's
actual archive/inventory/portable-member/lifecycle/checksum gates intact. Publish
only the three versioned installers as a prerelease with latest=false; verify
actual public download bytes afterwards. Stable2026.10.1 stays Latest. Stable
feature promotion and broader storage consolidation remain outside this scope.
