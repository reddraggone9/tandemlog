package com.reddraggone9.tandemlog

import java.io.IOException

/**
 * Standalone JVM boundary checks, compiled with the production helper:
 * kotlinc CheckedReplacement.kt CheckedReplacementCheck.kt -include-runtime
 *   -d replacement-check.jar && java -jar replacement-check.jar
 * No Android framework, test dependency, emulator or production data.
 */
fun main() {
    val before = byteArrayOf(1, 2, 3, 4)
    val after = byteArrayOf(8, 9)
    var checks = 0
    fun failure(phase: String, uncertain: Boolean, action: () -> Unit) {
        try {
            action()
            error("Expected replacement failure")
        } catch (error: ReplacementFailure) {
            check(error.phase == phase) { "Wrong phase: " + error.phase }
            check(error.mayHaveChanged == uncertain)
            checks++
        }
    }

    var current = before.copyOf()
    var writes = 0
    CheckedReplacement.replace(before, after, { current.copyOf() }, {}, {
        current = it.copyOf()
        writes++
    })
    check(current.contentEquals(after) && writes == 1)
    checks++

    current = byteArrayOf(0)
    writes = 0
    failure("source_changed", false) {
        CheckedReplacement.replace(before, after, { current }, { error("Unexpected probe") }, { writes++ })
    }
    check(writes == 0 && current.contentEquals(byteArrayOf(0)))

    current = before.copyOf()
    failure("prepare", false) {
        CheckedReplacement.replace(before, after, { current }, { throw IOException("Provider cannot sync") }, { writes++ })
    }
    check(writes == 0 && current.contentEquals(before))

    failure("source_changed", false) {
        CheckedReplacement.replace(before, after, { current }, { current = byteArrayOf(6) }, { writes++ })
    }
    check(writes == 0 && current.contentEquals(byteArrayOf(6)))

    for (partial in listOf(byteArrayOf(), after.copyOfRange(0, 1), after.copyOf())) {
        current = before.copyOf()
        failure("write", true) {
            CheckedReplacement.replace(before, after, { current }, {}, {
                current = partial.copyOf()
                throw IOException("Synthetic write/sync interruption")
            })
        }
        check(current.contentEquals(partial)) // no automatic retry or cleanup
    }

    current = before.copyOf()
    failure("verify", true) {
        CheckedReplacement.replace(before, after, { current }, {}, { current = byteArrayOf(7) })
    }
    check(current.contentEquals(byteArrayOf(7)))

    current = before.copyOf()
    var reads = 0
    failure("check", false) {
        CheckedReplacement.replace(before, after, { throw SecurityException("Grant revoked") }, {}, { writes++ })
    }
    check(current.contentEquals(before))

    failure("verify", true) {
        CheckedReplacement.replace(before, after, {
            reads++
            if (reads > 2) throw SecurityException("Grant revoked after write")
            current.copyOf()
        }, {}, { current = it.copyOf() })
    }
    check(current.contentEquals(after))

    failure("unsupported", false) {
        CheckedReplacement.replace(after, before, { current }, {
            throw ReplacementFailure("unsupported", false)
        }, { writes++ })
    }

    reads = 0
    try {
        CheckedReplacement.replace(before, ByteArray(CheckedReplacement.MAXIMUM_BYTES + 1),
            { reads++; current }, {}, { writes++ })
        error("Expected bound failure")
    } catch (_: IllegalArgumentException) {
        check(reads == 0)
        checks++
    }
    println("Checked replacement boundary: " + checks + " checks passed")
}
