# Desktop experimental installers

Release assets are a genuine single-file Flatpak bundle and a per-user
Windows installer. The exact candidate assets are installed and smoke-tested in
the reusable validation workflow, retained for five days, and consumed by the
publication job without rebuilding. APK acceptance/signing gates remain unchanged.
No stable release, signing service, credentials, paid runner, or Flathub submission
is introduced.

Public filenames include the release version. Runtime downloads use the official Flathub repository metadata.

## Linux

Install the downloaded bundle with `flatpak install --user ./tandemlog-<version>-linux-x64.flatpak` (replace `<version>` with the downloaded release version)
and launch `flatpak run com.reddraggone9.tandemlog`. The GNOME 50 runtime is
resolved from Flathub; the bundle alone is not a fully offline distribution.
Install an updated bundle with the same `flatpak install --user ./new-bundle.flatpak`
command and application ID. A different bundle commit updates the installed app
without removing its data. Reinstalling the identical deployed commit can report
`already installed`; it is not an update and needs no forced reinstall. Uninstall with
`flatpak uninstall --user com.reddraggone9.tandemlog`; do not delete your profile
or canonical folder. The package asks for desktop rendering/IPC and the two
specific native profile paths, with no network, whole-home or whole-host grant.

The launcher preserves `~/.local/share/com.reddraggone9.tandemlog` and its `data`
default canonical folder. Existing legacy `~/.local/share/tandemlog/settings.json`
is honored if the ID directory lacks settings, including an empty ID directory
created by Flatpak's permission grant. It never copies, migrates or rewrites
canonical history. The app's private cache/settings remain at their existing
native path; package uninstall does not own those files.

A custom sync folder outside the granted profile needs selection through the GTK
portal, or an explicit folder-scoped grant if the chooser/provider does not support
persistent directory access:

```sh
flatpak override --user --filesystem="/absolute/permanent/sync/folder" com.reddraggone9.tandemlog
```

Grant the existing permanent folder; do not relocate it or its Syncthing share.
An inaccessible saved folder produces the app's visible error/recovery path.
Custom native `XDG_DATA_HOME` can be preserved by granting its exact profile path
and setting the host data root explicitly, since Flatpak replaces `XDG_DATA_HOME`:

```sh
flatpak override --user --filesystem="/custom/data/com.reddraggone9.tandemlog" --env=TANDEMLOG_HOST_DATA_HOME=/custom/data com.reddraggone9.tandemlog
```

Explicit `TANDEMLOG_PROFILE` is also supported; supply it via `flatpak override
--user --env=TANDEMLOG_PROFILE=/absolute/profile` and grant that exact directory.
These overrides are optional only when using custom locations.

## Windows

Run `tandemlog-<version>-windows-x64-setup.exe` for the downloaded release version. It requires no administrator
permission, installs the full Flutter bundle under `%LOCALAPPDATA%\Programs\Tandemlog`,
and creates a Start Menu shortcut. The final wizard can launch the app. Windows
uses the same installer identity across versions. Stable `AppId=com.reddraggone9.tandemlog`
preserves replacement/uninstall registration across versions. The uninstall
routine removes installed program files and shortcuts, with no user-data deletion
rules. Existing profile and canonical folders are kept. The installer checks all three required system MSVC DLLs and the x64 runtime
registration before installing any files, requiring at least the compiler version
actually selected by CMake. If missing or too old, it stops with Microsoft's
[official runtime download link](https://aka.ms/vc14/vc_redist.x64.exe).
Runtime installation is a separate Microsoft installer and may require administrator
permission. Tandemlog does not download it, accept its license, or redistribute
Microsoft DLLs. Hosted native smoke covers a prerequisite-equipped Windows machine;
a clean-machine runtime installation has not been exercised.

Inno Setup is the
unmodified official compiler supplied by GitHub's standard Windows image. The
6.7.1 hosted compiler prints `Non-commercial use only`; the
[official licensing FAQ](https://jrsoftware.org/isorder.php) says purchasing a
commercial license is not strictly required and does not request a purchase from
noncommercial users. This experimental household app introduces no purchase or
new commercial distribution claim.

## Installation-warning troubleshooting

If an installation warning appears, retain its exact wording and confirm the download came from the intended GitHub release. The Windows installer and standalone Flatpak bundle currently have no publisher signature; Android uses the retained owner certificate. A checksum confirms bytes, not publisher identity. A normal Android permission prompt for installing from the chosen source differs from a harmful-app detection; report the latter before continuing. Do not disable security protections to suppress warnings. Trusted Windows signing or a signed Linux distribution repository is a later distribution decision, not introduced by these previews.

## Automated evidence and limits

Hosted Linux/Windows smoke gates install the exact candidate, launch the installed
application against synthetic settings/history, force a fresh SQLite projection,
exercise package replacement, uninstall, assert settings/history hash continuity,
reinstall and load again. Linux requires loaded-frame/task markers and captures the exact sandbox instance
ID through Flatpak’s instance-ID file descriptor. It kills that instance and waits
for it to disappear between phases; terminating the launcher alone could leave
the app holding its writer lock. It also requests `--die-with-parent` as a cleanup
backstop. No application-wide kill or data reset is used. Windows
requires a visible native window belonging to the installed process and the full
fresh projection. Windows checks every bundled payload file and the Start Menu
shortcut target. The reports record all four lifecycle phases and block
publication if incomplete. Windows rehearses same-candidate replacement. Linux first installs/launches the
exact public candidate, temporarily installs a private baseline with a distinct
OSTree commit subject but identical application payload and permissions, then
updates back to the untouched public candidate. Its gate verifies distinct commit
identities, equal baseline payload/permissions and restored candidate commit; every
recorded launch uses the public candidate. The private baseline is excluded from
release artifacts and involves no app recompile. This does not establish old-app-
version compatibility or manual Windows interaction acceptance. Windows uses an isolated synthetic profile override. Linux seeds the actual
native default profile/data paths on the disposable hosted runner, then launches
without an override or extra filesystem grant to verify the production wrapper
and default-folder permissions. Seeding refuses an existing directory; no test
reinstalls or modifies real data.

The cloud Linux workspace cannot run a Flatpak sandbox: `unshare -Ur true` fails
because `/proc/self/uid_map` is read-only. Native installed Flatpak and Windows
claims must come from the standard hosted jobs; Linux loose-binary checks do not
substitute for those jobs.

Primary references: [Flatpak sandbox permissions](https://docs.flatpak.org/en/latest/sandbox-permissions.html),
[single-file bundles](https://docs.flatpak.org/en/latest/single-file-bundles.html),
[Inno Setup privilege policy](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm),
[Inno Setup license](https://jrsoftware.org/files/is/license.txt),
[standard Windows runner software](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md).
