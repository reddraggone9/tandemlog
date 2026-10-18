package com.reddraggone9.tandemlog

import java.io.IOException

/** No distributed CAS: the coordinator must retain its durable byte journal. */
internal class ReplacementFailure(
    val phase: String,
    val mayHaveChanged: Boolean,
    cause: Exception? = null,
) : IOException("Checked replacement failed during " + phase, cause)

/** Pure byte/state boundary shared by SAF and deterministic failure tests. */
internal object CheckedReplacement {
    const val MAXIMUM_BYTES = 32 * 1024 * 1024

    fun replace(
        expected: ByteArray,
        replacement: ByteArray,
        read: () -> ByteArray,
        prepare: () -> Unit,
        write: (ByteArray) -> Unit,
    ) {
        require(expected.size <= MAXIMUM_BYTES && replacement.size <= MAXIMUM_BYTES)
        fun checkCurrent() {
            val current = try {
                read()
            } catch (error: Exception) {
                throw ReplacementFailure("check", false, error)
            }
            if (!current.contentEquals(expected)) {
                throw ReplacementFailure("source_changed", false)
            }
        }
        checkCurrent()
        try {
            prepare()
        } catch (error: Exception) {
            if (error is ReplacementFailure) throw error
            throw ReplacementFailure("prepare", false, error)
        }
        // The provider probe may take time. Recheck the selected pathname after
        // it, while acknowledging the remaining external sync race explicitly.
        checkCurrent()
        try {
            write(replacement)
        } catch (error: Exception) {
            throw ReplacementFailure("write", true, error)
        }
        val confirmed = try {
            read()
        } catch (error: Exception) {
            throw ReplacementFailure("verify", true, error)
        }
        if (!confirmed.contentEquals(replacement)) {
            throw ReplacementFailure("verify", true)
        }
    }
}
