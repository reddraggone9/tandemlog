# Stable update channels — development, not enabled

Goal: ordinary signed Linux updates and public Windows ZIP installation, with
household rollout only while idle. Lee authorized this after RC109; none of the
following changes an immutable release, public feed or owner device.

## Prepared source

`linux/build-flatpak.sh` can sign with an explicitly supplied existing approved
key/home/public key and embed the fixed GitHub Pages application repo-url. All
four options must be supplied together. It uses the existing app/master ref;
GNOME remains on Flathub. The synthetic install-replacement baseline exports to
a **separate QA repository**, never replacing the accepted channel ref. The
candidate repository is retained under RUNNER_TEMP, not yet uploaded/deployed.
No key is created by the build; default builds remain unsigned/no app origin.

`tool/update_channels.py` generates a Scoop bucket snapshot from exact matching
stable release/Latest receipts, requiring the original versioned ZIP's GitHub
URL and API SHA256. It cannot publish or install. The full ZIP exposes the CLI
and GUI; no package-relative persist directory or TANDEMLOG_PROFILE override.
Windows GUI therefore retains path_provider's normal roaming profile, writer,
folder selection and instance lock, shared with the existing Inno distribution.
RC launchers retain their deliberate isolated child-only profile override.
Do not run both distribution owners' automatic updaters for one installation.
License is CC0-1.0; MSVC runtime remains an external prerequisite.

## Remaining gates / concrete holds

- New long-lived Linux signing identity: `AGENTS.md` and `design/releases.md`
  require separate approval. Need custody/recovery/rotation plan, reviewed public
  pin, action-time credentials and exact candidate signing proof. Android signing
  identity does not establish a Flatpak signing key. None created here.
- Add clean repository artifact/provenance to candidate closed inventory and
  publication policy; keep its exact accepted OSTree commit. Implement serialized
  Pages deployment and signed summary/AppStream from accepted objects, not rebuild.
  Never deploy a prerelease or change stable channel before it becomes Latest.
- Unify public Windows ZIP staging (currently manual while private draft) and
  stable workflow before automating channel advancement. Never upload into an
  immutable release afterward. Do not claim a public Scoop bucket exists yet.
- Synthetic native Linux: signed bundle -> origin/key; next commit remote update;
  unsigned current bundle -> signed origin bootstrap in user AND system scope;
  interrupted/tampered/wrong signer refusals and retained profile/grants/identity.
- Synthetic native Windows: Inno->Scoop and Scoop updates/uninstall/reinstall,
  normal roaming identity/locks and separate RC profiles, clean runtime failure.
- Household flow still requires adapters and integration. Eligibility must be
  fresh local evidence of awake/idle/no recent input/no game/no media, with unknown
  signals deferring. Close Tandemlog is Lee-authorized, not force-kill pending
  writes. Recheck immediately before install, verify exact installed identity
  without opening live data, keep per-host durable pending/retry receipts. No
  WakeSystem/WakeToRun/WOL; Bender offline means retry when awake, not wake it.
  No current timer was changed or installed by this development increment.

These are exact remaining implementation/acceptance work, not a release claim.
