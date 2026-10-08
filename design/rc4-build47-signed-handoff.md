# RC4 build47 replacement handoff

Candidate application source remains frozen at `44344407200b61d38d7b33f22c0ace715376fd6f`, version `2026.10.2-rc.4+47`. This documentation branch preserves evidence without modifying that source. See the [receipt](../evidence/rc4-build47-signed/receipt.json) for exact current gates and [source-level release QA](../evidence/rc4-build47-signed/linux-release-qa/README.md).

## Dated authorization override

On 2026-10-08 parent relayed Lee's explicit waiver: RCs may ship without manual Windows testing for now, using Linux native acceptance as the shared desktop substitute. Full automated Windows tests and packaging lifecycle remain required. This overrides the pending Windows decision in the historical build47 preparation plan; that source-bound historical plan remains preserved. It does not waive stable acceptance. Lee requested finishing all remaining work before RC delivery. The local task owns Android spoken screen-reader acceptance and final replacement-package checks. Parent coordinates any eventual preview publication after all gates and a fresh quota read; no stable promotion is authorized.

## Source and editorial review

Architecture, correctness and security independently accepted the integrated reviewed UI fix; native, storage, domain, dependencies, signing and publication workflows remain unchanged. Architecture independently accepted the actual published RC3 source `5ac35da50acca69ab196a54312efc8ccef1452da` through replacement source443, seven concise notes bullets and unchanged tag image. One new bullet explains the compact bulk warning. A second Before/After release-note image is unnecessary for this small fix; engineering native Before/After evidence remains preserved. Exact notes/media hashes are in the receipt. Original earlier editorial receipts remain historical.

## Preserved original candidate and bounded renewed acceptance

Original build46 signed run37819214432 and its three artifacts remain preserved, explicitly superseded and unpublished. Parent's full core Android acceptance stays attributed to its exact build46 APK and packet. Build47 acceptance focuses on the changed bottom-scrolled bulk form, delayed incoming peer change, visible stale rejection, retained draft and repeated rejection without writes, Cancel→Discard, actual keyboard geometry, plus essential exact-package identity/signature/install/upgrade/startup/synthetic-data/cold-rebuild smoke. The already accepted core matrix is not repeated wholesale or relabelled as build47.

Actual Linux GTK release47 dark390×820 source-level QA passed both rejections, discard and cold rebuild with unchanged canonical and writer/settings hashes. Four final native integration regressions cover wide/narrow dark, narrow light/enlarged text/IME, and compact dark enlarged/IME. The previously documented extreme160px editor layout bound remains: warning can have zero height when wrapped actions consume the entire editor. It requires broader host/action layout work if actual small-window/landscape use exposes it, and before stable promotion.

Full main CI run37835589840 passed all three platforms at source443, including 634 Linux and 632 Windows unit tests (two named Linux-only skips), 74 Linux native flows, frozen native contracts and both installed lifecycles. Correctness independently accepted exact decoded logs, all four new native flows and terminal source binding. Main was freshly reverified at443 immediately before dispatching signed run37838800145 on main at20:21:13UTC; full repeated checks and owner signing are in progress. No candidate publication has been invoked.
