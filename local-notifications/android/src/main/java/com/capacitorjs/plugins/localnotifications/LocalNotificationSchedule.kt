package com.capacitorjs.plugins.localnotifications

import android.text.format.DateUtils
import com.getcapacitor.JSObject
import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

public class LocalNotificationSchedule() {
    public var at: Date? = null
    public var repeats: Boolean? = null

    // 'year'|'month'|'two-weeks'|'week'|'day'|'hour'|'minute'|'second';
    public var every: String? = null
    public var count: Int = 1
    public var on: DateMatch? = null

    private var whileIdle = false
    private var scheduleObj: JSObject? = null

    @Throws(ParseException::class)
    public constructor(schedule: JSObject) : this() {
        scheduleObj = schedule
        // Every specific unit of time (always constant)
        every = schedule.getString("every")
        // Count of units of time from every to repeat on
        count = schedule.getInteger("count", 1) ?: 1
        // At specific moment of time (with repeating option)
        buildAtElement(schedule)
        // Build on - recurring times. For e.g. every 1st day of the month at 8:30.
        buildOnElement(schedule)

        // Schedule this notification to fire even if app is idled (Doze)
        whileIdle = schedule.getBoolean("allowWhileIdle", false) ?: false
    }

    @Throws(ParseException::class)
    private fun buildAtElement(schedule: JSObject) {
        repeats = schedule.getBool("repeats")
        val dateString = schedule.getString("at")
        if (dateString != null) {
            at = parseJsDate(dateString)
        }
    }

    private fun buildOnElement(schedule: JSObject) {
        val onJson = schedule.getJSObject("on") ?: return
        on =
            DateMatch().apply {
                year = onJson.getInteger("year")
                month = onJson.getInteger("month")
                day = onJson.getInteger("day")
                weekday = onJson.getInteger("weekday")
                hour = onJson.getInteger("hour")
                minute = onJson.getInteger("minute")
                second = onJson.getInteger("second")
            }
    }

    public val onObj: JSObject?
        get() = scheduleObj?.getJSObject("on")

    public fun allowWhileIdle(): Boolean = whileIdle

    public val isRepeating: Boolean
        get() = repeats == true

    public val isRemovable: Boolean
        get() =
            if (every == null && on == null) {
                if (at != null) !isRepeating else true
            } else {
                false
            }

    /**
     * Get constant long value representing specific interval of time (weeks, days etc.)
     */
    public val everyInterval: Long?
        get() =
            when (every) {
                // This case is just approximation as not all years have the same number of days
                "year" -> count * DateUtils.WEEK_IN_MILLIS * 52

                // This case is just approximation as months have different number of days
                "month" -> count * 30 * DateUtils.DAY_IN_MILLIS

                "two-weeks" -> count * 2 * DateUtils.WEEK_IN_MILLIS

                "week" -> count * DateUtils.WEEK_IN_MILLIS

                "day" -> count * DateUtils.DAY_IN_MILLIS

                "hour" -> count * DateUtils.HOUR_IN_MILLIS

                "minute" -> count * DateUtils.MINUTE_IN_MILLIS

                "second" -> count * DateUtils.SECOND_IN_MILLIS

                else -> null
            }

    /**
     * Get next trigger time based on calendar and current time
     *
     * @param currentTime - current time that will be used to calculate next trigger
     * @return millisecond trigger
     */
    public fun getNextOnSchedule(currentTime: Date): Long? = on?.nextTrigger(currentTime)

    public companion object {
        public const val JS_DATE_FORMAT: String = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

        /**
         * Reads a date that JavaScript wrote with `Date.toISOString()`. Without an explicit locale the default one
         * chose the calendar, so that on a Thai device 2026 was read as a year of the Buddhist era, 543 years earlier.
         */
        @Throws(ParseException::class)
        internal fun parseJsDate(value: String): Date {
            val sdf = SimpleDateFormat(JS_DATE_FORMAT, Locale.US)
            sdf.timeZone = TimeZone.getTimeZone("UTC")
            return sdf.parse(value) ?: throw ParseException("Unparseable date: \"$value\"", 0)
        }
    }
}
