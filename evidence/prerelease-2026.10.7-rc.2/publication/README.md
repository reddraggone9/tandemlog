# Experimental 2026.10.7-rc.2/build91 publication

[RC.2](https://github.com/reddraggone9/tandemlog/releases/tag/v2026.10.7-rc.2)
published 2026-10-18T14:49:25Z from accepted source
`7b4ffba164207f4a029e3fda2e37c3559b436d61` as prerelease, not Latest.
Signed candidate [39125969801](https://github.com/reddraggone9/tandemlog/actions/runs/39125969801),
push [39125952688](https://github.com/reddraggone9/tandemlog/actions/runs/39125952688)
and [promotion 39137679534](https://github.com/reddraggone9/tandemlog/actions/runs/39137679534)
passed every required job. Promotion reused the three original accepted installers
without rebuilding. Reviewed notes came from docs-only dispatch
`c5cd0c051231e5fbb21de1fb2034b1f89477ccad`, SHA256
`3c37114317dd5a4d2124f0df5f806be79b9da9065221f3a278a53af3e70baf1c`.

[Public verification](public-verification.json) records actual anonymous downloads
equal to the accepted original Android APK, Windows installer and Linux Flatpak;
official owner APK signature, package/version/build91/nondebuggable status, three
ABIs, native text payloads, notices and unchanged permissions. Exact notes,
tag/source and prerelease flags pass. All 34 prior releases, notes, asset identities
and metadata (excluding mutable download counts), and every prior tag ref remain
unchanged. Stable2026.10.6/build85 remains Latest.

[Candidate acceptance](../candidate91/README.md) retains native coverage and limits.
This RC upgrades the local profile database from schema3 to schema4; stable/build85
and RC.1/build86 cannot reopen that upgraded profile. Existing v3 shared workspaces
stay v3. Unified v4 activation remains restricted to disposable trials.
Production conversion and stable promotion remain held. Private fixtures,
profiles, raw logs, screenshots and demonstrations stay external.
