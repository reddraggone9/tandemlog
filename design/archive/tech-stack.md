> Historical design from commit `1be49b4`; not an implementation specification.
> See [current design index](../README.md). Latest user direction and approved decisions take precedence.

# Tech Stack

This document records the current implementation path for Tandemlog.

## Primary Stack

- Language: Rust for the core logic and the great majority of the application code
- UI framework: Dioxus
- Synced data: per-node append-only JSONL logs, transported by Syncthing
- Local data: SQLite and JSON
- Platform-specific code: keep it thin and limited to OS integration points such as notifications, folder picking, and background behavior

## Platform Plan

### Initial implementation

- Windows desktop
- Android

### Soon™

- Web: secondary target
  - Primarily as a full-app browser automation target for end-to-end testing
  - Can also provide a no-install preview path
  - Feature coverage on web does not need to match native targets
  - Web capabilities should not drive architecture decisions
- Linux desktop: Before the first public release

## Web Plan

- Use official SQLite WASM with OPFS-backed persistence for the local cache layer
- Keep the file-based sync model and use polling to pick up changes; this will limit it to Chrome and derivatives

## Packaging Assumptions

- Android can start with sideload distribution
- Desktop releases should prefer self-contained application bundles
- Linux packaging details can be finalized closer to release, with Flatpak as a likely target for the public Linux release

## Testing Strategy

- Core unit tests: write these first and write them often. They should carry most of the confidence for replay ordering, conflict resolution, recurrence, sorting, timer behavior, and reminder logic.
- Storage and integration tests: add these alongside the storage layer. They should exercise JSONL ingestion, invalid tail handling, SQLite materialization, snapshot updates, and incremental rebuild behavior.
- UI component tests: add these for complex state transitions. They can dispatch events and verify the resulting UI updates using VirtualDom-driven tests. For example:

  ```rust
  #[test]
  fn due_kind_toggle_switches_label() {
    use dioxus::dioxus_core::{ElementId, Event, NoOpMutations};
    use dioxus::html::{
      set_event_converter, PlatformEventData, SerializedHtmlEventConverter,
      SerializedMouseData,
    };
    use dioxus::prelude::*;
    use std::{any::Any, rc::Rc};

    set_event_converter(Box::new(SerializedHtmlEventConverter));

    fn app() -> Element {
      rsx! { DueKindToggle {} }
    }

    let mut dom = VirtualDom::new(app);
    dom.rebuild(&mut NoOpMutations);

    let click = Event::new(
      Rc::new(PlatformEventData::new(Box::<SerializedMouseData>::default())) as Rc<dyn Any>,
      true,
    );

    // Assumes the toggle is the first element with a click listener.
    dom.runtime().handle_event("click", click, ElementId(1));
    dom.process_events();
    dom.render_immediate(&mut NoOpMutations);

    let html = dioxus_ssr::render(&dom);
    assert!(html.contains("Deadline"));
    assert!(!html.contains("Target"));
  }
  ```

- End-to-end tests: add these for core workflows once the native app is working. Prefer browser automation against the later web target for broad full-app coverage with less platform-specific harnessing.
- Platform smoke tests: keep a small set for platform-specific behavior that browser-based tests cannot cover.
