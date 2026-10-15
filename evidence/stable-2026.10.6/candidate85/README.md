# Stable 2026.10.6/build85 candidate preparation

Lee accepted experimental RC.1/build84 and explicitly authorized stable release
on2026-10-15. Accepted application source is `09d631ce073a4fd42e42c9baafd2a79ac3364845`; reviewed publication receipts
at `5f43700d0ea85975394cccfc22e992af631aa170` contain no intervening executable change. This candidate changes
only official version/build metadata to2026.10.6+85, matching stable Flatpak
metadata, stable notes and release evidence. Application source, tests, native
payload source, dependencies, platform adapters, signing pin, permissions and
durable v3 meanings remain unchanged from accepted RC.1.

Full signed-candidate/push CI, original artifact/source/version/signer/lifecycle
verification, exact retained Android84-to85 upgrade and affected native workflows,
canonical-byte/projection/settings/SAF preservation, source-qualified desktop
acceptance and independent review remain required. Return an acceptance handoff
with fresh quota before publication; this preparation does not publish a release.
Stable2026.10.5/build81 remains Latest. Earlier RC acceptance keeps its original
source/build attribution. Windows manual-GUI waiver, manual LinuxGTK AOT versus
hosted installed Flatpak and Android11/API30 x86_64/simulated-wide qualifications
remain explicit; no physical ARM/API36/general16KiB runtime claim is made.

Use isolated synthetic trials under6GiB/2CPU/zero-swap/one-emulator limits; restore
settings, remove temporary test links and stop temporary processes after acceptance
or blockers. Profiles, canonical snapshots and raw media stay private. No production
operation, held dependency/Base64 upgrade or unrelated feature work is included.
