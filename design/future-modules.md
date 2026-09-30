# Deferred directions

These are architecture inputs, not an approved roadmap or schemas.

## Games

Backlog, progress, notes and eventual recurring game activities. Start with separate game records and optional task references when requested; do not force all progress into task completion. External catalog integration and offline artwork/attachments require separate scope.

## Food logging and inventory

Lee confirmed nutrition includes adaptive expenditure estimation from weight and calorie intake to inform goals, alongside food logging. Before implementation, research MacroFactor’s public explanations and failure lessons; do not claim to reproduce its proprietary algorithm exactly. Catalog licensing, barcode/search quality, household privacy and offline availability may be larger product costs than UI implementation. No coaching algorithm or service is selected. Default household sharing is accepted; future private data belongs in a separate synced data space, not a filtered shared view.

Keep food definitions, consumed servings and inventory lots distinct. Each lot has units, quantity and optional expiration; unknown dates stay unknown, not model-invented. Use fixed-point/decimal quantities with explicit dimensions and conversion/rounding policy. Grams, milliliters, packages and servings are not freely interchangeable without recorded conversion data.

Stock is opening balance plus uniquely identified deltas. Two offline users consuming the last unit both count; show a deficit and reconciliation rather than losing one consumption with last-writer-wins or silently clamping to zero. Strict nonnegative global stock requires coordination/rights allocation; do not build that unless the product requires it. Count corrections need an observed baseline to avoid erasing concurrent consumption.

Food entry plus its inventory allocation should be one atomic logical command. Edits, undo and retries must reverse or amend the original linked effects exactly once, including partial portions and multiple lots. Defer automatic deduction until explicit logging and stock adjustment work reliably; first show a proposed allocation.

## Recurrence and dates

Separate date-only, floating local wall time, and pinned IANA-zone schedules. A due date is not midnight UTC; a calendar day is not always 24 hours. Decide daylight-saving gap/fold behavior, month-end rules, missed occurrences, schedule edits, and whether start/due offset means calendar or elapsed time. Natural-language rule text is display/input, not the canonical recurrence format.

A shared floating schedule can appear at different instants to traveling household members; decide whose zone anchors completion-based recurrence. Store actual completion instants and relevant zone context. Use stable occurrence identities so two offline completions of one occurrence do not advance the series twice. Specify deterministic resolution for competing completion times and schedule revisions. Rendering/replay must not independently emit “next occurrence” events on every device. Align timezone data/version policy so replicas do not silently diverge.

## Assisted capture

Walmart receipt → proposed products/lots/quantities; expiration photo → proposed date linked to a selected lot; voice → proposed task title, description, due date and recurrence. Receipt prices are not quantities, and receipt lines do not prove expiration dates. Show the evidence and ambiguity, allow correction, validate units/dates, and deduplicate retries before acceptance. See the [trust boundary](architecture.md#trust-and-privacy). Model availability must not prevent manual offline use.

Time tracking is separately [deferred](time-tracking-deferred.md).
