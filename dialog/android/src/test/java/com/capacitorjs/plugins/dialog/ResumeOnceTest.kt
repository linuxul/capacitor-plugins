package com.capacitorjs.plugins.dialog

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine
import kotlin.coroutines.suspendCoroutine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ResumeOnceTest {
    // The results the continuation was resumed with, in order
    private val results: MutableList<Result<String>> = Collections.synchronizedList(ArrayList())

    private val continuation =
        object : Continuation<String> {
            override val context = EmptyCoroutineContext

            override fun resumeWith(result: Result<String>) {
                results.add(result)
            }
        }

    @Test
    fun theFirstAnswerResumes() {
        val once = ResumeOnce(continuation)

        assertTrue(once.resume("ok"))

        assertEquals(listOf(Result.success("ok")), results)
    }

    @Test
    fun theDismissalAfterAnAnswerIsDropped() {
        val once = ResumeOnce(continuation)

        once.resume("ok")

        assertFalse(once.resume("dismissed"))
        assertEquals(listOf(Result.success("ok")), results)
    }

    @Test
    fun aDismissalWithoutAnAnswerResumes() {
        val once = ResumeOnce(continuation)

        assertTrue(once.resume("dismissed"))

        assertEquals(listOf(Result.success("dismissed")), results)
    }

    @Test
    fun answersFromSeveralThreadsResumeOnce() {
        val once = ResumeOnce(continuation)
        val threads = 8
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(threads)
        try {
            val resumed =
                (0 until threads).map { index ->
                    pool.submit<Boolean> {
                        start.await()
                        once.resume("answer $index")
                    }
                }
            start.countDown()

            assertEquals(1, resumed.count { it.get(5, TimeUnit.SECONDS) })
            assertEquals(1, results.size)
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun aSuspendedMethodReturnsTheFirstAnswer() {
        // As DialogPlugin uses it: the dialog answers, is dismissed after that, and the method returns the answer. A
        // second resume of the suspended continuation itself would throw "Already resumed".
        var dialog: ResumeOnce<String>? = null
        val method: suspend () -> String = { suspendCoroutine { dialog = ResumeOnce(it) } }
        method.startCoroutine(continuation)
        assertTrue(results.isEmpty())

        checkNotNull(dialog).resume("ok")
        checkNotNull(dialog).resume("dismissed")

        assertEquals(listOf(Result.success("ok")), results)
    }
}
