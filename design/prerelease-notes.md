# 2026.10.7-rc.3 — experimental

- Upgrade a shared workspace from Settings, with device consent and resumable progress.
- Task changes received while working in Food appear when returning to Tasks.
- Correcting the last validation error returns Add/Save immediately, including date and time selections.
- Enable CST6CDT, EST5EDT, MST7MDT and PST8PDT in Settings.

This RC upgrades the local app profile. Older app versions cannot reopen that
profile; keep using this RC or newer. Shared v3 workspaces stay on v3 until
explicitly upgraded. Workspace upgrades are forward-only.

Enabling the additional time zone names requires build98 or newer on every
device. Older apps stop opening that workspace; this setting cannot be disabled.
