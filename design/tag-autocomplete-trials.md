# Tag-entry alternatives — awaiting Lee's choice

Status: lightweight, isolated UI trials. Neither is adopted. This branch is based
on checklist candidate `eb68b46259f745e86ec9f41c144d473f19d0fb0f`; that candidate is
unchanged. Fresh quota approval was recorded at 07:07:23 UTC on October 8, 2026.

Filter already has searched multi-tag selection. These alternatives address the
task editor's **Tags** and bulk **Add tags / Remove tags**, which currently accept
space-separated text. Exact spelling, case and slash hierarchy remain intact;
spaces still separate tags. Optional leading `#` normalizes as in the existing editor. Matching ignores case, but selection inserts the
inventory's original spelling. This is presentation research with synthetic tags,
not a durable-format or tag-identity proposal.

| Choice | How it works | Advantage | Tradeoff |
| --- | --- | --- | --- |
| **A — Text completion** | Keep the current field. Suggestions complete the tag under the cursor; preceding and following tags remain. Use Up/Down and Enter, or click a suggestion. Continue typing spaces to enter more tags. | Compact; preserves current typing and paste habits; suits quick bulk deltas. | Selected tags and removal remain plain text; the current token is less explicit. |
| **B — Chips + query** | Selected tags become removable chips. Search separately, select a suggestion, or press Enter to add a new tag. Multiple space-separated new tags can be added together. | Clear selected set and explicit removal; existing and new tags are discoverable. | Takes more height, especially with many tags; editing spelling requires removal and re-entry. |

There is no clear winner across compact keyboard entry and visible selection.
Please choose **A** or **B** before a full implementation and its full tests.
An additional modal browser would largely repeat the existing Filter picker and
add a navigation step, so it was not one of the strongest two trials.

See the [actual Linux previews and recording](../evidence/tag-autocomplete-trials/README.md).
The experiment uses the real `TaskEditor` / `BulkTaskEditor`, app theme and editor
validation, with a small opt-in builder. The production host never supplies that
builder. The harness has no store, profile, sync adapter or persistence, and its
Save acknowledgement is explicitly a preview.

The popup opens upward in these trials because Tags is near the editor footer.
Production placement must use real viewport/keyboard bounds after the choice,
alongside IME composition, caret-token replacement, Escape/Tab, query draft
commit, stale inventory, errors, scrolling, keyboard focus, accessibility,
light/dark, large text, restart/save, and native Android/Windows acceptance.
These remain pending; the lightweight exploration does not claim release gates.

Run interactively:

```sh
source /workspace/toolchains/env.sh
flutter run -d linux -t tool/tag_trials/main.dart
```

The staged capture build additionally passes `--dart-define=TAG_TRIAL_DEMO=true`
to focus synthetic `ba` suggestions. That staging flag is confined to the harness.
