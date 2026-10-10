# Build59 Task inset correction

The initial build59 candidate ran all94 native cases:92 passed and two failed.
Both failures placed the Task bulk-edit stale-selection warning116px below the
simulated keyboard boundary after Save. The Food title/form matrix passed.
Signing was skipped. [Original failure](../../candidate/build59/source87-failed/manifest.json)
is preserved; that candidate cannot be promoted.

The correction restores the established Task Scaffold resizing policy whenever
Food is not visible. Food's modal handling and every existing test assertion
remain unchanged. The four original bulk cases reproduce two failures before
correction, then pass all four in28 seconds. They retain warning/action bounds,
exact draft/selection/focus/scroll, repeated Save, peer edits, canonical no-write
and discard assertions. [Dark200% warning](green-screens/bulk-failure-small-dark-200-ime-rejected.png)
and [light200% warning](green-screens/bulk-failure-narrow-light-200-ime-rejected.png)
show the reachable warning and actions above the280px simulated inset.

The corrected source also passes production Food Save/restart/restore and all
twelve Add/Edit1/Edit100, light/dark,100/200% title/form/error/IME combinations in
5:38. The final nonempty glyph-box assertion runs in this native rerun. There are
120 matrix captures, two production stock captures and two excluded warmups.
[Focused long-title editor](food-screens/keyboard-dark-2x-edit-100-title-and-name-ime.png)
and [complete dirty-close explanation](food-screens/keyboard-dark-2x-edit-100-discard-explanation-ime.png)
are actual GTK window captures. Independent review directly viewed all eight
changed matrix frames;112 match the previously reviewed captures byte for byte.

These are Linux GTK debug checks using synthetic fixtures and simulated keyboard
metrics. They do not attest Android Gboard or Windows GUI acceptance. The bulk
GREEN executable predicate precedes only its explanatory source comment; the
later Food run rebuilds the final commented source. The original Food
[manifest and demo](../keyboard-build59/README.md) remain unchanged and retain
their original source/fixture qualifications.

[Manifest](manifest.json) binds current source, unchanged fixtures, raw RED/GREEN
logs and every original image. Linux's40-minute budget retains the entire matrix
and packaging/lifecycle gates. Fresh full candidate, original artifact review,
parent exact Android acceptance and private publication clearance remain required.
