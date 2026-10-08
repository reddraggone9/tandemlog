# Approved deterministic Yrs adoption

Official yrs0.28.0 archive SHA256 52c70dc8beca8666c77612a96889106ca3cd65318609721f464624ff79685da9; source revision23b7f5693bbf9e7d26340c521ee8647f79bdfba2. All67 packaged files verified against actual registry bytes, retained exactly except approved undo.rs patch SHA2569d502e49d1dfacbefb713658295a18997a3fbc4951932eba70c6f174f52b7532. No generated target or registry marker copied. Patched undo.rs SHA2562e37cd3f1114822a18be6fc9cebd2acc3da79786a342bd0a528e9a4e8afb14f6.

Canonical and experiment wrapper Cargo overrides use one vendored source; both lock diffs remove only Yrs registry source/checksum. Original archive checksum remains in notices and provenance. Build gate pins inventory digest, all67 hashes and local override, and emits source inventory in build receipt. No new download/build hooks/dependencies. Existing authoritative upstream MIT license retained.

New3tests frozen before implementation: test-freeze.sha256, red.txt (2fail/1missing-file error), vendor-green.txt. Final35toolcases(original32+3),4noticecases,4Rustcases,98frozenPythoncases PASS against actual productionSO. Native tests have no skips. pycompile and owned diff whitespace checks PASS. Focused actual app/store closed-editor Undo regression PASS with exit0 in app-store-retry.txt using CI=true and writable XDG config. Initial run printed pass but CLI exit1; explicit CI rerun encountered shared disk-full while copying dill (app-store-final.txt). Removed only this task newly generated target/debug332MiB and retried successfully; historical evidence untouched. Root full app suite remains its own gate.

Fresh library: /tmp/tandemlog-yrs-adoption/linux/libtandemlog_text.so
SHA2565d0a7b1b3e0e6b906e831bed562a45f8db03a2bf4f08c80d9dc0c29a6f169153
Set TANDEMLOG_TEXT_LIBRARY to this exact file; no shared old-library path overwritten. Raw new logs reside here; historical fixture/performance evidence untouched. owned-files.txt enumerates77files (10tooling/docs/provenance+67officialsource). No app/domain/storage changes, commits or pushes by this agent.

Remaining gates: parent full app suite, platform rebuild/runtime/packaging against adopted source. Narrow sorted traversal fixes observed identity allocation divergence, not universal Yrs determinism. Maintenance exit documented in design/dependencies.md.
