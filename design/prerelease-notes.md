Experimental 2026.10.0-rc.1 task preview.

- Raw captures stay in Inbox until a saved edit; Undo restores the classification.
- Desktop setup uses a clearly named shared-data folder. Search/Add and task titles/metadata fit the compact interface; existing folder selections stay unchanged.
- A profile lock and installation writer guard protect local writing. Android imports use notifications and retained byte checkpoints, with a conservative fallback; Linux file creation gains directory durability barriers.
- Settings adds **Check data integrity**, with a full v3 record-chain check and copyable diagnostics. Ambiguous Android canonical filenames are refused.

**Test-data format break:** existing v1/v2 canonical folders are preserved but cannot open in this build. Back them up and use a separate v3 test folder, or coordinate fresh test contents across all participating apps/devices. There is no automatic conversion, reset or deletion. Markdown remains authoritative until a separately agreed cutover.
