# Task IME and recovery UX addendum

Accepted for the bounded Linux scope reviewed here. Actual390×800/200% shared-recovery pixels show readable heading, diagnostic and guidance, with Retry fixed and clearly separated at the bottom. Current narrow/wide Food stock captures remain consistent with the already accepted compact layout. FoodPage8219fa… is unchanged; the previous density receipt is preserved.

Final main6f5b37… hides the module selector only during active single/bulk Task editing with an on-screen keyboard, without font or touch-target shrink. Its predicate restores the selector when keyboard insets clear. The original IME regression body is byte-identical to Git HEAD, including caret/viewport checks, text scales1.0/1.3/2.0, single/bulk cases and repeated keyboard open/close. The mixed focused run passes this regression, fixed headers and tag-filter/block-drag checks. It also has two failures and is not an all-green run. No separate selector-node assertion or human keyboard journey was independently performed.

The narrow first-name setup exception retains private name/focus and existing Continue retry; the diagnostic scrolls within120px. Its retry revalidates shared authority before user creation. Later onboarding1/1 is green. Other stopped command surfaces remain blocked. This is a UX/source review, not a substitute for admission/security review.

Author-run outcomes: final production recovery5/5 green; focused Tasks3pass+2fail (historical recurrence async UI readiness; desktop onboarding focus); later onboarding1/1 green. Full87 Tasks remains running in the frozen checkpoint log and is not claimed complete. The recurrence failure still needs explicit final disposition.

All sources, images and raw logs are hash-bound in review-receipt.json. The reviewer independently viewed actual recovery and both stock images, read source/logs, and verified the unchanged IME body. No builds/tests/native launch were run by the reviewer. Parent confirms final production source/run binding; this receipt does not invent a separate build attestation.

No open must-fix UX defect was observed in this bounded followup. Exact-artifact, full Tasks result, Android/Windows, broader keyboard/accessibility and publication gates remain separate. Linux scripted test evidence is not human touch/device evidence; no private import or live synced-data action occurred.
