# 2026.11.0-rc.1 release-note media

Synthetic data; real Linux GTK app (Xvfb, private XDG runtime and DBus), Dark theme, 1x text.

| Image | Before | After | Capture |
|---|---|---|---|
| media/01-activity-list.png | v2026.10.11 (`d52a81d`) | `b58c83e` | 390x820 window, identical seeded history, Activity log open (raw/raw-{stable,rc}-list.png) |
| media/02-activity-details.png | v2026.10.11 (`d52a81d`) | `b58c83e` | same run, "Food edited" details (raw/raw-{stable,rc}-food-details.png) |
| media/03-successor-date.png | v2026.10.11 (`d52a81d`) | `05e49ee` | completion notice; that code is unchanged between `05e49ee` and `b58c83e` |

Recipe (01, 02): crop 390x680+0+60 from each capture, 34 px centered label bar
"Before (2026.10.11)" / "After (2026.11.0-rc.1)", 6 px divider, side by side.

Editorial review: first review found inaccurate and missing bullets and unusable
Activity media (Before was an unreleased build); notes were rewritten and the
Activity media recaptured against stable. Re-review found no notes in the
Markdown, a missing date/location separator on Food rows (introduced in
`6f354de`; fix deferred to the next candidate, so the Inbox image was dropped),
and a too-narrow bulk-edit bullet; all addressed.

The release moved to build 112 (`a2fc34c`) after these captures: an Activity
naming fix for captured tasks (create plus position in one record) and a
restored separator on Food rows. Neither affects what images 01–03 show: the
Activity fixture has no captured tasks and the images show no Food rows.
