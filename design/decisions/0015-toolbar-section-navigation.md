# Toolbar section navigation

Status: accepted by Lee on2026-10-11; implementation and focused native acceptance
are being prepared for the next Food preview. Stable promotion remains separate.

## Context and choice

The initial Food preview placed a full-width Tasks/Food switch above the existing
Tasks identity/count toolbar. This repeated the current section and consumed
vertical space on narrow screens. Lee approved using that existing identity as
the switch instead.

The toolbar trigger shows the current section icon, name and downward triangle
when space permits. Narrow layouts retain the icon and triangle, with a full
accessible current-section label. Actual available width and text size determine
fit equally on desktop and phone. Tasks retains its check-in-circle icon; Food
retains its fridge icon. The menu always names both sections and marks the current
selection. Each trigger retains a minimum48px target and native popup keyboard
behavior.

Section navigation remains distinct from account identity, filters and Food
views. Existing counts and actions remain in their section toolbar; Food Settings
joins that toolbar. An unavailable Food surface retains navigation and Settings.
Switching sections uses the existing dirty-editor guards, and choosing the
current section leaves its draft alone.

## Alternatives and consequences

The separate permanent switch repeats identity and uses scarce row space. A
second title row or bottom bar adds persistent chrome. Text-only narrow controls
require more horizontal space; icon-only menu choices hide names. The accepted
dropdown removes one permanent row while adding one step to section switching.

This is presentation and host navigation only, with no durable record, cache,
domain, dependency or sync changes. Revisit if actual native use reveals poor
discovery, inaccessible controls or insufficient space at enlarged text sizes.
