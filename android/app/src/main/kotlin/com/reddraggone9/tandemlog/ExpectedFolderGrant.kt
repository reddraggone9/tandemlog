package com.reddraggone9.tandemlog

/** Exact opaque SAF identity check must precede any persistent grant action. */
internal object ExpectedFolderGrant {
    fun retain(expected: String?, chosen: String?, grant: () -> Unit): Boolean {
        if (chosen == null || (expected != null && chosen != expected)) return false
        grant()
        return true
    }
}
