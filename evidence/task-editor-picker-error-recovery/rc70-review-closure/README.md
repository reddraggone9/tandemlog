# Build 70 editor regression closure

A rejected stale bulk Save could leave its warning outside the visible form on a small phone with enlarged text and the keyboard open. The existing failure notice now stays beside the retry/close actions, with a scaled body-line reserve and full-width wrapping only for the affected failed bulk modal. The existing callbacks, stale-write rejection, editing state and model/storage behavior are retained.

The phone workflow now uses Android touch metrics and scrolls an intentionally scrolling action into view before asserting its enabled 48dp target and keyboard-safe bounds. It retains caret, field, draft and canonical-write safeguards. Five native GTK bulk variants, the phone single/bulk workflow and all six previous picker-error/resize cases pass, as do 44 focused editor units; analysis is clean. Actual warning dragging exposes the full final phrase. Independent source and pixel review found no blocking issue.

These are actual Linux GTK pixels with simulated Android/IME metrics. Original signed Android acceptance and full hosted candidate gates remain separate requirements. Prior build 68 acceptance retains its original attribution. Private logs, captures and visible-input demo are retained outside source. No publication, live import, dependency change or PR8 merge is performed here.
