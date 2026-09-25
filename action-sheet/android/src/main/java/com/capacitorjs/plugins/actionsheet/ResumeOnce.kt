package com.capacitorjs.plugins.actionsheet

import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.Continuation

/**
 * Resumes [continuation] with the first answer it is given and drops the others.
 *
 * An action sheet reports more than once: an option reports its index and the sheet is dismissed after it, and a
 * sheet that is cancelled is dismissed as well. A continuation may resume only once, and the call it belongs to must
 * settle with the first answer.
 */
internal class ResumeOnce<in T>(private val continuation: Continuation<T>) {
    private val resumed = AtomicBoolean(false)

    /**
     * Resumes the continuation with [value]. False, doing nothing, when an earlier answer has resumed it already.
     */
    fun resume(value: T): Boolean {
        if (!resumed.compareAndSet(false, true)) {
            return false
        }
        continuation.resumeWith(Result.success(value))
        return true
    }
}
