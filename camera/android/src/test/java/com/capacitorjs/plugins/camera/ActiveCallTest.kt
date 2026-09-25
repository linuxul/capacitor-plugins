package com.capacitorjs.plugins.camera

import java.util.concurrent.Callable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveCallTest {
    private val activeCall = ActiveCall<Any>()
    private val first = Any()
    private val second = Any()

    @Test
    fun aCallBeginsWhenNoneIsInProgress() {
        assertTrue(activeCall.begin(first))
        assertTrue(activeCall.isActive(first))
    }

    @Test
    fun anotherCallIsTurnedAwayWhileOneIsInProgress() {
        activeCall.begin(first)

        assertFalse(activeCall.begin(second))
        assertTrue(activeCall.isActive(first))
        assertFalse(activeCall.isActive(second))
    }

    @Test
    fun theActiveCallIsConfirmedWhenAResultArrivesForIt() {
        activeCall.begin(first)

        assertTrue(activeCall.begin(first))
        assertTrue(activeCall.isActive(first))
    }

    @Test
    fun endingTheActiveCallLetsTheNextOneBegin() {
        activeCall.begin(first)

        assertTrue(activeCall.end(first))
        assertFalse(activeCall.isActive(first))
        assertTrue(activeCall.begin(second))
    }

    @Test
    fun aCallEndsOnce() {
        activeCall.begin(first)
        activeCall.end(first)

        assertFalse(activeCall.end(first))
    }

    @Test
    fun aCallThatEndedCannotEndTheOneThatBeganAfterIt() {
        activeCall.begin(first)
        activeCall.end(first)
        activeCall.begin(second)

        assertFalse(activeCall.end(first))
        assertTrue(activeCall.isActive(second))
        assertFalse(activeCall.begin(Any()))
    }

    @Test
    fun aCallThatWasTurnedAwayCannotEndTheActiveOne() {
        activeCall.begin(first)
        activeCall.begin(second)

        assertFalse(activeCall.end(second))
        assertTrue(activeCall.isActive(first))
    }

    @Test
    fun endingWithNoCallInProgressChangesNothing() {
        assertFalse(activeCall.end(first))
        assertTrue(activeCall.begin(second))
    }

    @Test
    fun clearEndsTheActiveCall() {
        activeCall.begin(first)

        activeCall.clear()

        assertFalse(activeCall.isActive(first))
        assertFalse(activeCall.end(first))
        assertTrue(activeCall.begin(second))
    }

    @Test
    fun onlyOneOfTheCallsBegunAtOnceBegins() {
        val threadCount = 16
        val calls = List(threadCount) { Any() }
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(threadCount)
        try {
            val results =
                calls.map { call ->
                    pool.submit(
                        Callable {
                            start.await()
                            activeCall.begin(call)
                        }
                    )
                }
            start.countDown()
            val began = results.map { it.get(10, TimeUnit.SECONDS) }

            assertEquals(1, began.count { it })
            assertTrue(activeCall.isActive(calls[began.indexOf(true)]))
        } finally {
            pool.shutdownNow()
        }
    }
}
