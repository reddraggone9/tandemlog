# Checklist controls follow-up

Baseline: released RC5 source `bc1fc99db53ef0ff9b9ad281ddefed4ea3bf234b`.
The follow-up fixes child long-hold drag interference, parent/child trailing
alignment, live Add checklist visibility, responsive outer row/divider inset,
and disclosure spacing. The toolbar action directly collapses shown checklists
when any is open, otherwise expands them, with the next action as its tooltip.

[Test-first/native receipt](linux-verification.json) binds six passing affected
native flows,23 focused widget tests and clean analysis. Corrected baseline
live-menu evidence fails on actual retained Add visibility; the earlier fixture
exception is not counted as a behavior red. The disclosure red measures16px
instead of the requested2px line gap. Final geometry includes tagged/untagged,
expanded/collapsed,599/600px boundaries,1200px desktop,360/390px enlarged text,
and asymmetric safe areas. The source uses content width after SafeArea.

[Independent correctness review](correctness-review.json) accepts the final UI
source. Domain, application, storage, text, native, dependency and workflow
implementation is unchanged. Synthetic isolated stores are used for all tests;
expansion checks compare canonical bytes and preserve hidden-parent state.

Native measurements show adjacent48px parent menu/reorder controls and aligned
child delete/reorder centres. No additional menu-to-handle gap existed before. A singleton parent retains an
inert reorder slot while its checklist is shown, so its menu stays above child
Delete even without a task reorder neighbor; a48px baseline mismatch is covered.
Disclosure count starts2px below the last body line; separate48px targets do
not overlap. At normal text size the count occupies20px, leaving26px below it.
Further compression would shrink the target or overlap its neighbor. A black
standalone toggle PNG is explicitly excluded from visual proof.

Signed-candidate/platform checks, exact Android affected-flow/demo acceptance,
fresh quota remain publication gates. The [assembled notes/media review](../rc6-editorial/editorial-review.json)
is complete, including immutable links and public200/hash verification. This
receipt does not grant Android/Windows runtime or stable-promotion acceptance.

The18.1-second [actual native Linux desktop demo](native-linux-pointer-demo.mp4)
shows a1.2-second held drag moving Map above Water bottle and Undo restoring it,
menus, immediate collapse/expand and390px layout. [Observed source/inputs](desktop-demo-verification.json)
bind the prepared RC6 source/version. The [7s frame](native-linux-pointer-frame.png)
shows the desktop pointer at the Map handle. This is not Android acceptance.

Candidate37887365667 at `c8596f22fd56ce0b73c74e1e5010337556b269e1`
failed the full Linux native aggregate (80 passed,6 failed), so build49 has no
signed APK. Three test-navigation helpers now centre gesture targets clear of
pinned group headings; existing assertions remain and shared selection requires
a real hit before acting. Replacement build50 retains the same production UI
sources. The build49 debug demo and figures remain evidence for those unchanged
UI sources, with their original source/version attribution.
The [aggregate navigation receipt](aggregate-test-navigation-verification.json)
binds the hosted failure, local reproduction and six formerly failing native
flows passing in2m48s with clean analysis. Full replacement platform gates remain
required.
