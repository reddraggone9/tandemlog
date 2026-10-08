# Initial capture rank

Approved fix: newly captured tasks start at the first shared manual position and
retain that rank after leaving Inbox. Multiline captures preserve entered order.
Existing creations, their v3 bytes and the scalar/manual-order projection retain
their released meaning. New captures add ordinary `task.moved` records before the
observed first task, in the same append as creation; an empty task sequence needs
no move.

Frozen red commits precede implementation. `red/rank-and-partial.txt` contains
scalar/native order failures plus a creation-only acknowledgement failure;
`red/native-inbox-triage.txt` disables only the new move emission as a negative
control and shows the actual GTK row dropping below an older organized task;
`red/native-prefix-reconciliation.txt` shows the original ID buffer being lost on
automatic refresh; `red/native-reservation-staging.txt` shows an individually
retryable native creation surviving a failed whole-capture reservation.

Final checks: **589 Flutter tests**, **4 actual Linux GTK Inbox workflows**, clean
analysis/format, and tooling checks in `green/`. Ten focused rank gates cover
scalar/native captures, prior manual reordering, Inbox exit, untouched legacy
bytes, completed/other-assignee anchors, duplicate capture calls, concurrent peer
arrival, reversed provider listing, fresh cache, multiline complete prefixes,
native preparation failure and staging failure. The corrected native fixture
uses legal Flutter lifecycle transitions and asserts no unhandled exception.

Creation and completed capture are distinct acknowledgements. A partial creation
is reported as confirmed created; its immutable input IDs remain read-only until
the original placement suffix is confirmed. Background refresh applies the same
completion rule. Native creation intents are staged only after the complete
capture reservation. A later staging failure with a suffix absent from provider
history remains fail-closed under existing manual writer recovery; these changes
do not claim automatic reconstruction/resending of a missing reserved suffix.

`ui/after-triage.png` and `ui/prefix-pending.png` are actual GTK pixels from the
passed native workflows, Linux x64 debug, 1000×820, light theme, normal text.
Inspected: new organized task precedes the older organized task; partial capture
shows a truthful creation/unfinished notice and retained retry buffer. The dated
task still sorts ahead of Someday, as required. No clipping or overlap observed.

The native library used by headless tests is the reviewed
`/workspace/toolchains/shared-history-native/libtandemlog_text.so`, SHA256
`a9b0c51f4f6cf347e321d9f47a0dec6161be161adfca44eb5be60c7db7a37e56`.
Native source/dependencies and frozen stable v3 fixture bytes are unchanged.

`tool/initial_rank_qa_fixture.dart` makes a fresh synthetic fixture with two
organized native tasks deliberately reordered B before A; refuses existing output
directories. Use `TANDEMLOG_TEXT_LIBRARY` with the reviewed engine and copy its
shared folder into a fresh app profile for platform acceptance. On Windows and
Android: capture two lines, save each title/notes without a date, verify their
entered order remains above B/A after Inbox exit, restart, and repeat after peer
reorder/import. Include prefix/unknown-ack recovery where the fixture transport
supports it. Android/Windows native acceptance and Android demo remain pending;
Linux evidence does not stand in for those platforms. No publication/push by the
implementation agent.


The 50.8-second `ui/initial-rank-linux-gtk-debug.mp4` is the real Linux GTK
main application at source `48ca813caabbf6317acdb5c5713f74d1a472f0c8`, dark,
1200×850, with actual X11 pointer/button/keyboard input. Only idle pauses were
removed; the original recording and original synthetic shared/profile fixture
are retained in `/workspace/recovery/initial-rank-demo-3f132607`. A frame extracted
from the final MP4 was inspected to verify the input pointer is visible. The
flow captures two lines, adds notes (including Save at an interrupted-edit
prompt), and leaves both new tasks above the previously reordered B/A tasks
after exiting Inbox. `dark-before-capture.png` and `dark-after-triage.png` are
states within this same fixed-source workflow, not comparative old/new builds.
The generated initial canonical fixture and its hashes are in `qa-fixture/`;
`ui/demo-metadata.json` records the exact platform, source, input and video hash.

Independent gates accepted: architecture reviewed the unchanged historical
projector, additive ordinary moves, bounded prepared-creation validation and
recovery paths, and passed 32 focused native rank/writer-guard tests. Security
accepted the repaired host reconciliation and native reservation admission after
its two focused gates. The parent independently verified the 589-test and
4-workflow green logs, inspected the actual light/dark PNGs, and decoded final
demo frames at 4/27/49 seconds: visible pointer/I-beam, interrupted Save prompt,
First/Second above Earlier B/A after triage, and truthful retained prefix notice.
No remaining must-fix was reported. Final ffprobe duration is **50.8 seconds**.
