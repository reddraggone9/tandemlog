# Pass 6: quiet pairs, host floor, and a recommendation to stop

**No production source change. Source remains 48b01b1d.** No release, device install or live profile; synthetic Linux runs on Bender only.

**Recommendation: stop chasing the remaining gaps.** The strict goal (no UI-isolate gap over 16.7 ms from launch to first list) cannot be met on this host by any app change: a bare Flutter app fails it in the same two places, by the same amounts. What the branch still has above that floor is small, partly also on origin/main, and not something a person can see.

## 1. Paired runs on a quiet machine (the parity question passes 3-5 left open)

Same harness and bundles as pass 3 (`bundle-base` = origin/main, `bundle-pass3b` = 48b01b1d), serial interleaved pairs, one strict and one warm launch per binary per pair, nothing else of ours running. Load average 2.3-3.0 throughout (`load-pass6.txt`, `load-pass7.txt`); passes 3-5 ran at 5-30.

| Batch | Mode | Max gap, main | Max gap, branch | Gaps > 16 ms per launch (count / total ms), main | same, branch | Launch to first list, main | branch | Paired difference (branch - main) |
|---|---|---|---|---|---|---|---|---|
| p6 (8 pairs) | strict | 762 ms (726-834) | 30 ms (24-41) | 7-8 / ~1,080 | 4-9 / ~120 | 2074 ms (2008-2223) | 2073 ms (1935-2268) | median -9, mean -18 ms |
| p6 (8 pairs) | warm | 59 ms (56-64) | 34 ms (29-39) | 7-9 / ~265 | 5-6 / ~145 | 362 ms (352-404) | 397 ms (358-401) | median +26, mean +25 ms |
| p7 (6 pairs, Roboto visible to Fontconfig) | strict | 778 ms (732-865) | 33 ms (27-37) | 7-9 / ~1,080 | 3-9 / ~135 | 2131 ms (2021-2231) | 2183 ms (1916-2276) | median +69, mean +13 ms |
| p7 | warm | 57 ms (55-62) | 33 ms (29-46) | 8-9 / ~265 | 5-6 / ~145 | 356 ms (350-365) | 403 ms (367-435) | median +48, mean +42 ms |

- Strict: the ~760 ms freeze is gone (30 ms worst gap) at the same launch time (differences of either sign inside a +/-200 ms run-to-run spread).
- Warm: worst gap 59 -> 34 ms, but **the branch is 25-48 ms slower to the first list (7-13 %) in 13 of 14 pairs.** That breaks the "not slower than origin/main" condition for the everyday launch. The time is in the history phase (ends at ~317 ms vs ~270 ms on main: background-owner jobs and 8 ms validation slices cost more wall time than one synchronous block); the first-list frame itself is ~28 ms shorter.
- p7 tested whether Bender merely lacks Roboto (so every match walks a fallback list). It does not help: with Roboto installed for the run (`fc-roboto-fonts.conf`), each new weight still costs a ~17-23 ms Fontconfig call. The cost is Fontconfig matching against the fonts installed on Bender (698 faces), not a missing family. Pass 3 wording that blamed the fallback list is wrong.

## 2. Where the branch still exceeds one frame, per launch

From the 28 branch launches above (`p6-after-*.txt`, `p7-after-*.txt`):

| Gap | Size | On main too? | What it is |
|---|---|---|---|
| Entry, [0, ~21] | 19-29 ms, every launch | yes (23-34) | Flutter engine/binding start and the first frame, before anything is on screen |
| Warm only, at ~80 ms | 22-46 ms | yes (28-49) | Pass 5: no CPU samples on the UI isolate in it; not our Dart code as far as the profile can show |
| Two font matches, at ~165 and ~200 ms | 17-27 ms each | inside main first-list frame instead | One Fontconfig call each (Linux only), moved out of the list frame on purpose |
| First-list frame | 23-41 ms, typically 28-32 | yes, 56-85 | First build/layout/paint of the list |
| Strict only, sporadic | 17-24 ms, 0-4 per launch | hidden inside the 760 ms freeze | An 8 ms validation slice plus whatever lands next to it |

## 3. Host floor: a bare Flutter app

`control/main.dart.txt`: a new `flutter create` app (same Flutter SDK, release build, same Xvfb/openbox setup, same 1 ms heartbeat class) that shows the same loading screen (title plus LinearProgressIndicator) for 400 ms and then a plain 200-row `ListView.builder` of `ListTile`s. No storage, no isolates, no plugins. 8 launches each way (`control-result.txt`, load ~10-13 from ZFS writes at the time; an earlier batch at load ~17-24 gave the same picture):

| | Entry gap | First-list frame | Largest gap in between |
|---|---|---|---|
| No font warm-up | 20-22 ms | 43-54 ms (median 49) | 13-32 ms |
| With the same font warm-up as the branch | 20-24 ms | 30-41 ms (median 33.5) | 12-26 ms |
| Tandemlog branch (p6/p7) | 19-29 ms | 23-41 ms (typically 28-32) | see table above |

So on Bender, under Xvfb, an app that does nothing already has a ~21 ms gap at entry and a ~33 ms first-list frame even with fonts pre-matched, and its idle progress-bar frames alone produce 10-20 ms gaps. The branch first-list frame is at or under that. Those two gaps are the floor of this host and toolkit, not Tandemlog work. (This also means every number here is a Bender figure: software rendering under Xvfb, 698 fonts. A phone has neither Fontconfig nor Xvfb; nothing in this investigation measured one, because no install was allowed.)

## 4. Cost/benefit

What more work could still buy, on Bender: the warm ~80 ms gap (22-46 ms, cause unknown after a symbolized profile, also on main), the two ~20 ms font calls (cannot be split or moved off the UI isolate; removing them puts ~45 ms back into the list frame), a few 17-24 ms slices on the rare strict open, and the warm 25-48 ms launch-time regression. None is a visible stall: during loading the only thing moving is an indeterminate progress bar, and the first-list frame replaces the whole screen, so there is no motion for a 30 ms frame to interrupt. Five passes produced one accepted design (pass 3) and three rejected experiments (batch inserts, bundled fonts, sequential decode); the remaining items have no identified cause that an app change would remove, and the floor above says the 16.7 ms target is out of reach here regardless.

What the branch (48b01b1d) is, if merged as it stands:
- Benefit: the strict open no longer freezes for ~0.75 s (bar keeps moving); strict opens are rare (no valid seal, failed fast check, older store; design/history-store.md). Everyday warm launch: worst gap 59 -> 34 ms and time spent in over-one-frame gaps ~265 -> ~145 ms.
- Cost: everyday launch 25-48 ms slower on Bender; about 2,600 changed lines in main.dart and the storage core, including SQL run on background isolates that borrow the UI connection inside an open transaction. That is covered by 12 new tests and the 1,938-test suite, and save atomicity and publication order are unchanged, but it is new machinery in the commit path. CI on 48b01b1d: Linux, Android, performance and workflow jobs passed; the Windows job was cancelled on that run and passed on the next run (dd1f25c5, same production source). No phone or Windows frame timing exists.

Options, in the order I would take them:
1. **Stop here and leave the branch unmerged** unless the strict-open freeze matters enough to accept the warm cost. By the stated conditions the branch does not qualify (warm is slower).
2. Merge it for the strict-open freeze, accepting ~+30 ms on warm launches, after a side-by-side phone check (needs an RC install, which this task could not do) confirms the phone shows the same trade.
3. Keep chasing warm parity: would need a restructure of the warm history phase with no identified mechanism; not recommended.

## Verification

No source change, so no new build of the app and no test run this pass; 48b01b1d stands at analyze clean and 1,938 tests passed (pass 3, re-run in pass 5). The control app is not part of the repo build; its source is kept here as text.
