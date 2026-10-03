# 0008 — Calendar versions and explicit stable promotion

Status: accepted by Lee, 2026-10-03. Tooling is implemented for validation;
stable publication requires separate explicit acceptance.

Use `year.month.patch`, unpadded month, optional dotted `-rc.N`, and a separate
monotonically increasing integer build: `2026.10.0-rc.1+38`. Patch and RC counters
identify revisions within the month; the build never resets with calendar changes.
Tags omit `+build` and installers include the display version. Protocol, cache and
private-metadata versions are independent of these release names.

The former `0.1.0-rc.N` names remain valid only when reading historical build
floors. Every changed signed candidate must exceed published and successful
unpublished candidate codes. Windows binary version resources use year, month,
patch and build as four unsigned 16-bit values; preflight fails above 65535
instead of truncating. This deliberate bound also applies to the installer.
[Microsoft's resource specification](https://learn.microsoft.com/en-us/windows/win32/menurc/versioninfo-resource)
and [Inno Setup's numeric version directive](https://jrsoftware.org/ishelp/topic_setup_versioninfoversion.htm)
define those fields. Revisit the Windows mapping before approaching the build
limit; do not silently reset Android's version code.

RC promotion consumes the exact successful all-platform candidate and native
accepted APK without rebuilding, marked prerelease and not Latest. Stable
promotion requires a separately built stable-name candidate, the same integrity,
installer and exact-artifact gates, required target acceptance, and an explicit
Lee-accepted operator attestation. It never relabels an RC APK as stable. The
stable workflow exists to make an eventual authorized promotion reviewable;
adding it does not authorize dispatch. [Release policy](../releases.md) owns
commands and gates; [schema](../schema.md) owns permanent-data compatibility.

Calendar naming makes the release date visible without claiming semantic-version
API stability. Keep stable decoder/hash compatibility regardless of version name.
Rejected: reset build numbers each month, truncate Windows fields, or drop native
acceptance for a stable-name rebuild.
