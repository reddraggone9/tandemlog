# Release-tooling review — 2026-11-13

Reviewed `5268ac3` and the follow-up `02cb56e` (HEAD when the review ended) in `/home/nibbler/tandemlog-rc-20261113`, against the private scripts in `tandemlog-stable116-20261107/`, `tandemlog-next-20261104/publish115/` and the q16 originals (`tandemlog-next-20261104/reference/q16/`, `tandemlog-next-20261103/reference/launch_reference_r8.py`). Nothing was published, the checkout was not edited, and no qualification or admission was run.

## Verdict

**Not a pass for the RC.** The publication tools only do stable, so the RC cannot go through them. Stable publication and the qualification helpers pass, with the notes below.

A tested fix for findings 1–4 is in `rc-kind.patch` beside this file (`git apply --check` passes on `02cb56e`).

## Fix before the RC

1. **RC is not supported.** `tool/publish-stable.py` hard-codes `RELEASE_KIND=stable` and `LEE_ACCEPTED_STABLE=true`, requires `--lee-accepted`, creates the draft without `--prerelease` or the "— experimental" title, asserts `not rel['prerelease']`, and finalizes with `make_latest=true`. `tool/verify-public.py` asserts `not release['prerelease']` and that Latest is the new release. An RC tag fails closed at `verify_release_kind`, so nothing wrong can be published, but there is no checked-in way to draft, finalize or publicly verify an RC. Build 115's RC did that with `publish115/finalize.py` and an RC variant of `verify-public.py` (prerelease true, Latest still the frozen prior release); neither was ported.
   - The documented workflow route does not cover this either. `prerelease.yml` publishes `design/prerelease-notes.md` unchanged, and those notes use relative `(media/...)` links, so the direct route would publish dead image links. The `draft_release_id` route still needs a hand-made draft, finalize and verify.
   - Fix: let the tag choose the channel. An `-rc.N` tag runs the gates with `RELEASE_KIND=prerelease`, needs no `--lee-accepted`, creates the draft with `--prerelease` and the title `TAG — experimental`, finalizes with `prerelease=true, make_latest=false`, and checks Latest did not move. `verify-public.py` expects prerelease and the frozen `prior-latest.json` id for an RC, and the current behavior for a stable.

2. **Notes are no longer tied to a commit on main.** The prior script read `git show <main>:design/stable-notes.md` and compared it byte-for-byte with the reviewed notes; `prerelease.yml` reads them from the dispatch commit. The new `--notes PATH` reads any working-tree file, committed or not. Fix: read `design/<prerelease|stable>-notes.md` from the policy revision and drop `--notes`.

3. **The policy revision can be stale or not main.** The prior script took main's SHA from the GitHub API and the workflows require `refs/heads/main`. The new default is the local `origin/main`, and `--policy-revision` accepts any ref. Fix: refuse unless it equals `git ls-remote origin refs/heads/main`.

4. **Media links are pinned to the candidate commit and never checked.** Step 4 of `design/releases.md` allows a notes fix on main after the candidate. Images added that way would not exist at the candidate commit, and only `verify-public.py` would notice, after publication. Fix: pin to the commit the notes come from and `git cat-file -e` each image before creating the draft.

### What the patch does

- Touches `tool/release_context.py`, `tool/publish-stable.py`, `tool/verify-public.py`, `tool/test_release_tooling.py` and `design/releases.md`.
- The stable path keeps the same gate inputs and the same finalize call.
- Adds six tests: RC draft (prerelease gates, title, notes from main, pinned media), RC publish never sets Latest, RC refuses a non-prerelease draft or a moved Latest, stable still requires `--lee-accepted` and refuses a prerelease draft, a stale main refuses before any state is written, and public verification for an RC.
- Tested on an export of `02cb56e`: 24 of 24 pass. Five of the new tests fail against the unpatched tools.

RC commands after the patch:

```sh
python3 tool/freeze-prior.py --repo-dir REPO --tag v2026.11.2-rc.1 --output EVIDENCE
python3 tool/verify-candidate.py --repo-dir REPO --tag v2026.11.2-rc.1 --output EVIDENCE --dist DIST --source FULL_SHA --build-tools ANDROID_BUILD_TOOLS
python3 tool/publish-stable.py --repo-dir REPO --tag v2026.11.2-rc.1 --output EVIDENCE draft --dist DIST --run-id RUN_ID --android-sha256 ACCEPTED_APK_SHA
python3 tool/publish-stable.py --repo-dir REPO --tag v2026.11.2-rc.1 --output EVIDENCE publish
python3 tool/verify-public.py --repo-dir REPO --tag v2026.11.2-rc.1 --output EVIDENCE --build-tools ANDROID_BUILD_TOOLS
```

`verify-candidate.py` needs `REPO` checked out at the candidate commit. The draft step needs `origin/main` fetched, `GH_TOKEN` exported and no egress proxy in the environment: the private scripts read the token file and stripped `*_proxy` themselves, and the new ones inherit the caller's environment.

## Passes

- **`freeze-prior.py`, `verify-candidate.py`:** work for any tag, including an RC. The dropped literals (expected Latest tag, version and build) are now derived from the source or recorded. `freeze-prior.py` gained a no-overwrite guard.
- **`verify-public.py`, stable path:** keeps every prior check and adds the public APK signer and version check. The fixed image count is replaced by a per-image check against the pinned commit.
- **`publish-stable.py`, stable path:** same gates and order as the 116 script; adds name, tag and notes-hash checks before finalizing.
- **`stable.yml` removal:** nothing else references it.
- **Tests:** `test_release_tooling.py` passes 18 of 18 at `02cb56e`. The full `tool/test_*.py` run on a non-git export: 303 run, 3 skipped, 2 errors, both `test_food_fixture_checkout` needing a git repository; not verified inside a real checkout.
- **Qualification helpers:** apart from parameterization, the shell scripts and launcher match q16. The pressure-policy hash, the 1500 s and 20 s bounds, the one-shot checks, the plan comparison and the seal checks are unchanged. The limits and controller hashes now come from the source profile, which still holds the q16 values (`142b4e4f…`, `f5e6262e…`).
- **Failure evidence before `reset-failed`:** correct.
  - `reset_owned` runs after cleanup, finalize, the independent readback and `executor-result.json`.
  - It checks both units are inactive with no main PID, writes `unit-results-before-reset.json`, and only then resets units that are `failed`.
  - An active or non-`tandemlog-reference-*` unit raises before anything is written or reset.
  - The fuller unit fields, `Result` and `ExecMainStatus` included, are already in the `status-NNNN.json` snapshots and `independent-final.json`.
  - A reset does not reopen a request: the claim markers and the existing output and evidence directories still refuse a relaunch.
- **`02cb56e`:** correct. The `5268ac3` `prepare.sh` read `PACKAGE_CONFIG` from the environment under `sudo -u nibbler`, which drops it; it is now an argument. The environment check now calls the gate's own `check_environment`.

## Smaller items, not blocking

- **Reset failure is reported inconsistently.** A `reset_owned` error is added after `executor-result.json` is written. The launcher exits non-zero, but the result file still says ready and `seal` would accept it. Recommendation: record `unit-reset-error.json` and leave the launcher exit alone, since the measurement is valid and the unit stays visibly failed.
- **Root now imports a second file from the checkout.** `launch_reference.py` puts its own directory first on `sys.path` and imports `unit_cleanup.py`, which the plan's `launcherSHA256` does not cover. Moving the 20-line function into the launcher restores the single hashed file.
- **Where to run qualification from.** `nibbler` has no sudo, and `lee` gets git's "dubious ownership" error on the nibbler checkout, so `prepare` fails there. It also refuses the checkout while `evidence/prerelease-2026.11.2-rc.1/` is untracked. Run from a lee-owned clone of the same commit, as q16 did.
- **Image coverage in `verify-public.py`.** Only pinned `.png` links are checked; a relative or non-PNG image is skipped silently. Optional: assert the count equals the number of `![` in the notes.
- **Stale text.** The docstrings in `freeze-prior.py` and `verify-candidate.py` still say `python3 -I` and "next to this script"; `-I` now fails on the `release_context` import. `prepare.sh` line 60 still names `coordinate-q16.sh`.
