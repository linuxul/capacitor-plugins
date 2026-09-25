package com.capacitorjs.plugins.camera

/**
 * The one getPhoto or pickImages call the camera plugin works for at a time. The plugin keeps that call's settings and
 * files in its own fields, so a call that began while another is in progress would take them over; [begin] turns it
 * away instead.
 *
 * The plugin thread begins a call, and the main thread (prompt, picker, activity and permission results) and the
 * plugin's executor (image work) end it, so every function is synchronized. Calls are told apart by identity: the
 * bridge hands the activity and permission callbacks the instance the plugin method got.
 */
internal class ActiveCall<T : Any> {
    private var call: T? = null

    /**
     * Makes [call] the active call, or confirms that it is. False, changing nothing, when another call is in progress.
     */
    @Synchronized
    fun begin(call: T): Boolean {
        val active = this.call
        if (active != null && active !== call) {
            return false
        }
        this.call = call
        return true
    }

    /**
     * Whether [call] is the active call.
     */
    @Synchronized
    fun isActive(call: T): Boolean = this.call === call

    /**
     * Ends [call], so that the next call can begin. False, changing nothing, when [call] is not the active call: a call
     * that has ended already cannot end the one that began after it.
     */
    @Synchronized
    fun end(call: T): Boolean {
        if (this.call !== call) {
            return false
        }
        this.call = null
        return true
    }

    /**
     * Ends the active call, if any, for when the plugin goes away.
     */
    @Synchronized
    fun clear() {
        call = null
    }
}
