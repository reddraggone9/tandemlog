# Agent interface final performance validation

The retained final advisory run on original source `aefa95b` completed 2026-10-30T01:06:04Z: all 256 absolute labels on all three shapes and both growth comparisons passed, correctness accepted, all pins match, zero reruns. This measure-only result is **not** reference qualification. Dense-food purchase import median/max 676.388/691.756 ms (budget700/1000); complete/edit/Undo medians466/464/466 ms (budget500/750).

Before controller registration, linear `a15941b`, tree-equivalent `094cfa8` and original `aefa95b` all have relevant-source-v2 identity `cb9b467279fa54ed04d4f726e2591837bfc7975cf56015945e92b4d12b31f3c0`. Qualification must bind this linear history's registration descendant, not the original merged branch.

The reviewed R7 controller changes only its hard-coded limits digest from894f3af1… to335cdc94…; hash1780871b…. Original controller, pressure module, caps, admission, lifetime and cleanup policies are unchanged. No budget loosened. **Reference qualification NOT QUALIFIED; release blocked.**

- q1 (`767260cc…`, linear source`24f2927`): all absolute labels passed, but Food history-growth `food.product.merge` median8.532ms exceeded8.52125ms. Failed original result retained.
- One bounded Food-products family diagnostic did not reproduce: large median6.585<=8.815ms; max7.869<=12.084ms. First diagnostic refused before measuring because its native-library environment binding was missing; that refusal was retained privately and corrected once.
- Standing-policy `authorize-rerun` accepted exactly one official unchanged-source q2 (`c4d1baa7…`), with authorization retained. q2 failed **dense-food `agent.write.purchaseImport2` median747.336ms >700ms** (max754.942<=1000ms). All other absolute labels and both growth comparisons passed. q1 import had passed684.101ms; q2 merge growth passed5.293<=9.120ms. No third qualification, budget change, owner override or passing receipt.
- Both controlled invocations used the reviewed caps/deadlines; no in-invocation retries or disk resamples. Inputs unchanged; original units MainPID0, processes absent, no swap/OOM, deadlines met. Failed-workload cleanup correctly refuses qualification (`verifiedCompletionCapture:false`); it is not a passing receipt.

`failed-q1/`, `failed-q2/` retain original source-bound requests, gate results and cleanup (plus q2 authorization); `diagnostic/` retains the nonqualifying result/record. Raw logs/controller/pressure/executor evidence remain private under `vex-agentrc-20261029`. Previous `reference-performance/current/` is retained historical evidence and **does not qualify this identity**. No CI/signing/publication/main/stable/live-data action was taken.

Next owner work: diagnose/fix import performance on changed source, then fresh qualification under unchanged policy; another unchanged-source rerun is not authorized. Private exact checkpoint: tandemlog-agent-reference-20261029/CHECKPOINT.md.
