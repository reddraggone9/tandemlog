package com.reddraggone9.tandemlog

/** Standalone checks run with the production ExpectedFolderGrant helper. */
fun main() {
    val expected = "content://synthetic/tree/expected"
    var grants = 0
    check(!ExpectedFolderGrant.retain(expected, null) { grants++ })
    check(grants == 0) // Cancellation.
    check(!ExpectedFolderGrant.retain(expected, "content://synthetic/tree/wrong") { grants++ })
    check(grants == 0) // No persistent permission action for wrong folder.
    check(ExpectedFolderGrant.retain(expected, expected) { grants++ })
    check(grants == 1)
    check(ExpectedFolderGrant.retain(null, "content://synthetic/tree/ordinary") { grants++ })
    check(grants == 2) // Ordinary picker retains its existing behavior.
    var denied = false
    try {
        ExpectedFolderGrant.retain(expected, expected) { throw SecurityException("Synthetic denial") }
    } catch (_: SecurityException) {
        denied = true
    }
    check(denied && grants == 2) // Permission failure never claims success.
    println("Expected folder grant boundary: 5 checks passed")
}
