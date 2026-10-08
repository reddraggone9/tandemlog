# Android collaborative-text preview QA

Use a fresh disposable synthetic profile and data folder. This experiment has
the normal application ID but a temporary debug certificate; it cannot update
the owner-signed app. Do not uninstall an existing app or open a live household
space to run these checks. No preview publication follows from this checklist.

## Exact intermediate package

- [Run37254495743/artifact11321533518](https://github.com/reddraggone9/tandemlog/actions/runs/37254495743/artifacts/11321533518), application source `cdbc56b9a53412591afbe0f71c0578d220abb3b9`.
- APK SHA256 `1a073a0f8bdf91378c20dcb5050026fd31381ed3b8292e38851939749e1983aa`.
- Debug signer SHA256 `863fe1068327311e9befaea24c41ce19e8e2c38518570ce9cfcbbf7e5a101199`.
- `com.reddraggone9.tandemlog`, code45/name2026.10.2-rc.3, three ABIs.

Verify the downloaded APK with official `apksigner verify --print-certs` and
SHA256 before installing on the explicitly selected test emulator. Record its
Android version/API/ABI and actual keyboard. This package predates the subsequent
performance optimization; retain that distinction in results. The final exact
candidate still requires its own installed smoke test.

## Affected workflows

1. Select a fresh SAF data tree, create a synthetic user and capture a task.
   Edit title and notes using the real OS keyboard, including composition,
   selection/replacement, multiline notes and Save/Cancel. Verify no receipt is
   submitted while composition is active. Injected composition alone is not OS
   keyboard evidence.
2. Add a recurrence and due date. Complete through the checkbox: exactly one
   successor appears with inherited title/notes. Edit that child, save, use
   session Undo, and restart the process. The parent stays completed and the
   child's acknowledged state persists. Test both title and notes.
3. Where two independent test installations are available, exchange **only** the
   canonical manifest/per-writer logs through their test folders. Keep SQLite,
   settings, installation writer identity and guards private. Make offline
   parent edits/completions, then child work before delayed peer arrival.
   Expect one child, completion-observed text union, preserved private draft and
   convergence. Later parent edits absent from every completion proof must not
   automatically enter the child.
4. Check selective Undo after peer work. It preserves original character
   ownership, not necessarily a later whole rendered title:
   `A → local BC → peer DC → local Undo = AD`. Independent append control:
   `AB → AXB → AXBY → local Undo = ABY`.
5. Force-stop/reopen with the retained SAF grant and ingest an externally
   replaced test log. Verify subsequent local writes and unique receipt IDs.
   Preserve any failed fixture, logs and private state for diagnosis; do not
   reset them to make a test pass.

Existing scalar tasks use active-user menu → Settings → **Set up shared text
editing**. Coordinate upgraded writers and read the confirmation before choosing
Set up. Newly captured tasks use native text without that legacy setup. The
historical scalar/native successor case currently rejects before append; see
[the decision proposal](historical-recurring-text-policy.md).

Enable Show taps for the short native video and verify inputs are visible.
Report exact APK/hash, passed and unrun cases, observed receipts and retained
state. Production-store multiwriter tests complement single-device UI checks;
they do not prove a provider, physical phone or OS keyboard behavior.
