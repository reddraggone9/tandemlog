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

The candidate workflow can retain its exact OSTree repository as a separate
`linux-flatpak-repo` artifact outside the closed `dist` inventory, behind repository
variable `TANDEMLOG_FLATPAK_CHANNEL` (unset). `tool/flatpak_channel.py site` lays out
Pages files only for the current stable Latest whose bundle digest matches that
repository, and refuses an unsigned summary or another signer. The manual **Advance
stable update channels** workflow deploys that site. Neither has ever run: there is
no key, Pages source or variable. Public release assets now include the original
portable ZIP in the first upload, when the candidate has its gated evidence.

`tool/household_update_policy.py` decides per host from supplied signals: unknown or
stale evidence, recent input, a game, media or pending writes defer; idle with
Tandemlog open closes it first; asleep defers, and only a host marked wakeable may be
woken once overdue (Lee 10-30). It reaches no host and has no adapters yet.

## Remaining gates / concrete holds

- **Blocked on Lee: new long-lived Linux signing identity.** `AGENTS.md` and
  `design/releases.md` require separate approval, with a custody/recovery/rotation
  plan. Android signing does not establish a Flatpak key. None was created, and no
  throwaway key either, so `site`'s signature check is unexercised against a real
  signature. After approval: provision a main-gated signing job (validate.yml must
  not hold the key), pin the public key and fingerprint in variables, enable the
  variable, then prove the path below on a synthetic channel.
- Serialized Pages deployment exists; signed summary/AppStream preservation across
  versions and retaining earlier objects (a site is one candidate's repo) still
  need design. Never deploy a prerelease or advance before it becomes Latest.
- Do not claim a public Scoop bucket exists yet; `tool/update_channels.py` only
  writes a private snapshot.
- Synthetic native Linux: signed bundle -> origin/key; next commit remote update;
  unsigned current bundle -> signed origin bootstrap in user AND system scope;
  interrupted/tampered/wrong signer refusals and retained profile/grants/identity.
- Synthetic native Windows: Inno->Scoop and Scoop updates/uninstall/reinstall,
  normal roaming identity/locks and separate RC profiles, clean runtime failure.
- Household rollout needs per-host signal adapters, verification of the exact
  installed identity without opening live data, and durable receipts. Bender offline
  means retry when awake. No current timer was changed or installed by this work.

These are exact remaining implementation/acceptance work, not a release claim.
