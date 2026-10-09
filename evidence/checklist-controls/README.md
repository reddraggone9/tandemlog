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
independent notes/media review and fresh quota remain publication gates. This
receipt does not grant Android/Windows runtime or stable-promotion acceptance.
