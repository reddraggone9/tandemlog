# RC4 editorial review

Covered executable range: published preview
`5ac35da50acca69ab196a54312efc8ccef1452da` through frozen combined candidate
`e205e650b5614935a73cf5acb96ca9b36fda8e4e`. This branch changes only notes and
engineering evidence; it does not mutate either acceptance target.

Independent correctness reviewer inspected the actual range and
`design/releases.md` editorial rules, then the six-bullet draft, comparison,
both raw PNGs, geometry, identical capture harness and logs. Accepted substantive
coverage and media: all nine receipt hashes verified; the two crops match raw
RGBA pixels exactly; both actual GTK captures passed 1/0 at 1200x850, Dark, scale1.
Labels are centered and readable, crops show the tag control, and the fixture
contains synthetic content only. Existing-task setup is stated; Filter suggestions
are described as shared with editors/bulk, rather than newly introduced in Filter.

The one comparison explains the visible editor tag change. Checklist, ordering,
spacing and accessibility changes are concisely described in prose; additional
UI scales and engineering captures remain outside the public notes. Kotlin build
tooling, internal performance, tests, expected interactions and preservation
assurances are deliberately engineering-only under the established editorial policy.

Media is committed at `89cec5a13900291df9f1cb841c5351277f38f4ff`; the draft now
uses its immutable raw image URL. Independent final link review closed the
editorial gate: remote HTTP200 returned the exact reviewed PNG (9566 bytes,
SHA256 `8a635aecffc81584d3153d77fbb0c8480a10b805df19ebf7b966e464179e3a90`),
and GitHub Contents API confirms the pinned source/blob identity. `media-receipt.json` records exact sources, raw captures and the
vector/crop layout recipe. Failed renderer attempts remain preserved separately
under `/workspace/recovery/rc4-media-render-rejected`; they are not published media.

This does not establish full composed CI, Android/Windows signed installed-release
acceptance, parent A16 regression acceptance, final UX audit, fresh quota or
publication eligibility. The candidate source and its pending native retest stay
frozen. No signing or publication was performed; stable promotion is unauthorized.
