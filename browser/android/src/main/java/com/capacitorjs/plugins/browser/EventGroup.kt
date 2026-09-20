package com.capacitorjs.plugins.browser

/**
 * Simple class to handle indeterminate sequence of events. Not thread safe.
 */
internal class EventGroup(private val completion: EventGroupCompletion?) {
    internal fun interface EventGroupCompletion {
        fun onGroupCompletion()
    }

    private var count = 0
    private var isComplete = false

    fun enter() {
        count++
    }

    fun leave() {
        count--
        checkForCompletion()
    }

    fun reset() {
        count = 0
        isComplete = false
    }

    private fun checkForCompletion() {
        if (count <= 0) {
            if (!isComplete) {
                completion?.onGroupCompletion()
            }
            isComplete = true
        }
    }
}
