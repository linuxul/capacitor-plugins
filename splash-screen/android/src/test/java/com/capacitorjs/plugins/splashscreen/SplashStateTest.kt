package com.capacitorjs.plugins.splashscreen

import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SplashStateTest {
    // The test thread stands in for the main thread
    private val owner = Thread.currentThread()
    private val state = SplashState { Thread.currentThread() === owner }

    @Test
    fun theSplashStartsHidden() {
        assertFalse(state.isVisible)
        assertFalse(state.isHiding)
        assertFalse(state.keepsLaunchSplash)
    }

    @Test
    fun theLaunchSplashIsKeptWhileItIsVisible() {
        state.isVisible = true

        assertTrue(state.keepsLaunchSplash)
    }

    @Test
    fun theLaunchSplashIsKeptWhileItFadesOut() {
        // What the exit animation of the Android 12 splash sets
        state.isHiding = true
        state.isVisible = false

        assertTrue(state.keepsLaunchSplash)
    }

    @Test
    fun hiddenEndsBothVisibleAndHiding() {
        state.isVisible = true
        state.isHiding = true

        state.hidden()

        assertFalse(state.isVisible)
        assertFalse(state.isHiding)
        assertFalse(state.keepsLaunchSplash)
    }

    @Test
    fun anotherThreadCannotReadTheState() {
        assertThrowsOnAnotherThread { state.isVisible }
        assertThrowsOnAnotherThread { state.isHiding }
        assertThrowsOnAnotherThread { state.keepsLaunchSplash }
    }

    @Test
    fun anotherThreadCannotChangeTheState() {
        assertThrowsOnAnotherThread { state.isVisible = true }
        assertThrowsOnAnotherThread { state.isHiding = true }
        assertThrowsOnAnotherThread { state.hidden() }

        // Nothing changed
        assertFalse(state.isVisible)
        assertFalse(state.isHiding)
    }

    private fun assertThrowsOnAnotherThread(block: () -> Unit) {
        val other = Executors.newSingleThreadExecutor()
        try {
            other.submit(Callable { block() }).get(5, TimeUnit.SECONDS)
            fail("Expected an IllegalStateException")
        } catch (ex: ExecutionException) {
            val cause = ex.cause
            assertTrue("Unexpected $cause", cause is IllegalStateException)
            assertEquals(
                "The splash screen is used from thread ${threadName(other)}; only the main thread may use it",
                cause?.message
            )
        } finally {
            other.shutdownNow()
        }
    }

    private fun threadName(executor: ExecutorService): String =
        executor.submit(Callable { Thread.currentThread().name }).get(5, TimeUnit.SECONDS)
}
