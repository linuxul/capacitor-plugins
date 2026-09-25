package com.capacitorjs.plugins.dialog

import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.Continuation

/**
 * Resumes [continuation] with the first answer it is given and drops the others.
 *
 * A dialog reports more than once: a button reports its answer and the dialog is dismissed after it, and the back
 * button cancels the dialog and then dismisses it. A continuation may resume only once, and the call it belongs to
 * must settle with the first answer.
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
