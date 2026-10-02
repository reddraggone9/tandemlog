Experimental RC8 task preview.

- Completed tasks use ordinary checked boxes. Reopening a repeating task restores its arrow outline.
- True Undo of recurring completion retracts an untouched next occurrence. Independent successor changes or dependencies are preserved and explained; checkbox Reopen still retains the next occurrence.
- Failed reopening no longer shows a success notice, and another concurrent completion is explained when it keeps the task completed.

Compatibility: same app identity and Android signer, protocol2 with a new closed-schema Undo event, and cache9. Update every peer before using the new recurring-completion Undo; earlier apps fail explicitly on that event. Known older local caches rebuild automatically without changing canonical history or writer identity. Historical Undo records retain their previous meaning.
