# Tech Stack

This document is for choosing the app's implementation stack.

## Decision Goal

Pick an approach that supports the product behavior and the storage/sync design without committing prematurely to a specific implementation before the user-facing behavior is better understood.

## Decision Criteria

- good support for local files and directory watching
- good support for local SQLite access
- ability to work well offline across target device types
- reasonable fit for background work and long-running state
- acceptable packaging and distribution story across target platforms
- maintainable shared code where it matters

## GUI Candidates

- https://github.com/DioxusLabs/dioxus
- https://github.com/emilk/egui
- https://github.com/slint-ui/slint
- https://github.com/makepad/makepad
- https://github.com/TheRedDeveloper/ply-engine

## Inputs

- [Product Behavior](./product-behavior.md)
- [Storage & Sync](./storage-and-sync.md)
- [Data Model](./data-model.md)

## Status

Undecided.
