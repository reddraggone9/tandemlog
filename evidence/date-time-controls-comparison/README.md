# Real native date/time control comparisons

The primary comparison shows the already shipped change from **Add time** in
2026.10.2-rc.1 build43 to the always-visible **Time** field in
2026.10.2-rc.2 build44. It is not a new change in the next candidate.

The secondary comparison separately shows build44's enlarged-text stacking
versus the isolated content-measured stacking experiment. It is unpublished.

All screenshots come from actual native Linux GTK/Flutter debug runs, using
full historical source snapshots for builds43/44, plus the committed candidate.
The same harness supplies matching synthetic task data, green light app theme,
viewport, text scale, and blank times. The main comparison is390px/100% text;
the secondary is520px/200% text. The time input/button targets measure at least
48px high. Crop geometry is captured from the live widgets; Pillow only crops
real pixels and adds report labels. It does not create or alter application UI.
Raw captures, geometry, source closure, native logs, the harness and the rendering
recipe are retained in this folder. See `source-closure.json` for exact revisions.

Reproduction: archive each recorded Git revision into an isolated source folder,
copy the supplied harness to `integration_test/date_time_controls_comparison_test.dart`,
source `/workspace/toolchains/env.sh`, and run:

```sh
DISPLAY=:99 DATE_CONTROLS_OUT=/tmp/comparison-before DATE_CONTROLS_OLD=1 flutter test integration_test/date_time_controls_comparison_test.dart -d linux --reporter expanded
```

Use `DATE_CONTROLS_OLD=1` only for build43; omit it for build44 and the candidate.
Each run needs the existing native Xvfb/Openbox session, `xdotool`, and ImageMagick
`import`. A separate per-snapshot `/tmp` build directory prevents workspace disk
pressure. Copy raw/geometry files under their phase prefixes, then run
`python3 make_comparison.py` to regenerate the two labeled artifacts.

These are native Linux images. They are not Windows or Android captures, and
do not establish Android IME/device acceptance. No install artifact, published
release note, production branch, signing configuration or release was changed.
