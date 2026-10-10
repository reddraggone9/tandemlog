# Food view reachability — build60

Actual Linux GTK/Flutter debug evidence for the bounded Food-page replacement.
This is synthetic data, 320×640 logical pixels, both themes,100/200% text and
SDK Roboto. Android acceptance and the fresh full candidate remain pending.
The title stays fixed; view/search controls, filters, notices, guidance and lazy
rows share a viewport. Main, editor/group commands and durable data are unchanged.

The corrected baseline fixture selects the actual vertical viewport: original
755 source leaves2px in the Roboto widget check and26px in GTK, below the48px
action requirement. Both return exit1. Earlier horizontal-scroll-selector and
whole-paragraph-fit investigations are debugging only and excluded from this
acceptance bundle. The separate fixed-controls IME probe finds110px overflow;
keeping view/search in the same scroller closes that bound too.

Final40 widget cases and analysis pass. Final native runs the same40 variants
plus real synthetic production Save/restart/Restore: two tests pass in4:08,
with all seven source hashes equal before/after. It proves ordinary vertical
swipes reach first/last Inbox actions and complete saved name/Needs expiration,
nonempty untruncated glyph endpoints for guidance/long notices, Retained reason
popup selection/clearing/expansion, explicit Deleted Restore with the physical
ID, eight empty views and preserved state. Search with simulated IME is explicitly
revealed by the fixture: this is assisted reachability/draft/no-overflow evidence,
not automatic Android caret acceptance. The earlier149 focused Food passes retain
their earlier fixture binding; final40 strengthens the saved-name assertion.

There are184 final actual PNG captures, with two additional warmup captures
excluded. Eight actual density captures retain64px normal rows/10 complete groups,
136px narrow enlarged rows/three groups and104px wide enlarged rows/five groups,
all with48px actions. Its viewport measurement now includes the control/header
sliver, unlike the old rows-only ListView metric. Density passes separately.

[35-second demo](native-linux-build60-inbox-pointer-demo.mp4) is an actual
320×640 crop/excerpt of the full native recording,15fps, with the actual X pointer
visible. It shows scripted independent synthetic fixture transitions, beginning
with dark200 Inbox and followed by dark100 Stock/error/Inbox. It is not a continuous
user Save/replay workflow, physical touch, Android or Windows execution.
The complete recording and four decoded sample frames are retained.

The [manifest](manifest.json) binds original bytes, source/test/build hashes and
the exact executed fixture. Private parent Android raw images, packet/profile
data, Library transfer metadata and quota values are excluded. Parent-reported
build59 Android acceptance keeps its original source/APK attribution in the
[current handoff](../../../../design/food-native-acceptance.md).
Final independent review receipts live beside the candidate/build60 checkpoint.
Stable2026.10.3 remains Latest; neither59 nor60 is published here.
