# Prerelease 2026.10.10-rc.1 / build107

- [RC](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.10-rc.1), release 428741281, published 2026-10-30T07:11:22Z: immutable prerelease, not Latest. Stable 2026.10.9 remains Latest; all 44 prior releases and tags are unchanged ([anonymous verification](public-verification.json)).
- Source `a61f6a98311eda2a2a7a2c035937a0d93bf48fb6`. Reference qualification `50a8ca56dd…` of `e212575` passed with zero reruns and resamples; budgets are unchanged. Its receipt is `evidence/reference-performance/current/`. Failed q1/q2 and the superseded q3 remain retained ([history](../agent-interface-performance/README.md)).
- CI 41009249480 passed. Signed candidate 41009283931 passed on attempt 2: attempt 1's Windows job hit its 40-minute limit on a runner 2.6x slower than concurrent CI of the same source (1,175 common tests, 2,635 s against 1,019 s), and one `rerun --failed` was used. Earlier CI failures preserved: 41002767100 (receipt omitted its ignored logs) and 41002954790 (test environment lacked `APPDATA`).
- Promotion 41018462411 attached the three gated installers to a private draft; the original portable ZIP was added and all four verified before finalizing.
- Native acceptance of the exact signed artifacts, synthetic data: Android 11/API 30 x86_64 emulator stable106→107 in place (first install time, SAF grant and old log bytes retained), and GTK Flatpak 2026.10.9→2026.10.10-rc.1 including the packaged CLI, a planned commit and MCP. Source-bound GTK and Android workflow runs (light/dark, wide/narrow, 200% text) ran at `c651d2b`; only test and evidence files changed after that.
- Separate editorial review PASS on the unchanged notes, SHA-256 `0920a9ba…`.

Not covered: physical devices, ARM, TalkBack; Windows has CI install-smoke evidence only. Raw native evidence is private.

Follow-ups for the next release: the "An earlier food save needs confirmation" banner flashes during every Food write (also on stable 2026.10.9); Move some's focused field clips at Android 200% text with the keyboard up, and location suggestions cover its buttons until dismissed; Enter in the GTK Move some location field does nothing; `agent_cli_test` runs up to 16 s against a 30 s default timeout on Windows.
