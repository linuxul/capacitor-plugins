package com.capacitorjs.plugins.localnotifications

import java.util.Calendar
import java.util.Date

/**
 * Class that holds logic for on triggers
 * (Specific time)
 */
public class DateMatch {
    public var year: Int? = null
    public var month: Int? = null
    public var day: Int? = null
    public var weekday: Int? = null
    public var hour: Int? = null
    public var minute: Int? = null
    public var second: Int? = null

    // Unit used to save the last used unit for a trigger.
    // One of the Calendar constants values
    public var unit: Int? = -1

    /**
     * Gets a calendar instance pointing to the specified date.
     *
     * @param date The date to point.
     */
    private fun buildCalendar(date: Date): Calendar {
        val cal = Calendar.getInstance()
        cal.time = date
        cal.set(Calendar.MILLISECOND, 0)
        return cal
    }

    /**
     * Calculates next trigger date for
     *
     * @param date base date used to calculate trigger
     * @return next trigger timestamp
     */
    public fun nextTrigger(date: Date): Long {
        val current = buildCalendar(date)
        val next = buildNextTriggerTime(date)
        return postponeTriggerIfNeeded(current, next)
    }

    /**
     * Postpone trigger if first schedule matches the past
     */
    private fun postponeTriggerIfNeeded(current: Calendar, next: Calendar): Long {
        if (next.timeInMillis <= current.timeInMillis && unit != -1) {
            val incrementUnit =
                when (unit) {
                    Calendar.YEAR, Calendar.MONTH -> Calendar.YEAR
                    Calendar.DAY_OF_MONTH -> Calendar.MONTH
                    Calendar.DAY_OF_WEEK -> Calendar.WEEK_OF_MONTH
                    Calendar.HOUR_OF_DAY -> Calendar.DAY_OF_MONTH
                    Calendar.MINUTE -> Calendar.HOUR_OF_DAY
                    Calendar.SECOND -> Calendar.MINUTE
                    else -> -1
                }

            if (incrementUnit != -1) {
                next.set(incrementUnit, next.get(incrementUnit) + 1)
            }
        }
        return next.timeInMillis
    }

    private fun buildNextTriggerTime(date: Date): Calendar {
        val next = buildCalendar(date)
        year?.let {
            next.set(Calendar.YEAR, it)
            if (unit == -1) unit = Calendar.YEAR
        }
        month?.let {
            next.set(Calendar.MONTH, it)
            if (unit == -1) unit = Calendar.MONTH
        }
        day?.let {
            next.set(Calendar.DAY_OF_MONTH, it)
            if (unit == -1) unit = Calendar.DAY_OF_MONTH
        }
        weekday?.let {
            next.set(Calendar.DAY_OF_WEEK, it)
            if (unit == -1) unit = Calendar.DAY_OF_WEEK
        }
        hour?.let {
            next.set(Calendar.HOUR_OF_DAY, it)
            if (unit == -1) unit = Calendar.HOUR_OF_DAY
        }
        minute?.let {
            next.set(Calendar.MINUTE, it)
            if (unit == -1) unit = Calendar.MINUTE
        }
        second?.let {
            next.set(Calendar.SECOND, it)
            if (unit == -1) unit = Calendar.SECOND
        }
        return next
    }

    override fun toString(): String =
        "DateMatch{year=$year, month=$month, day=$day, weekday=$weekday, hour=$hour, minute=$minute, second=$second}"

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false

        other as DateMatch

        return year == other.year &&
            month == other.month &&
            day == other.day &&
            weekday == other.weekday &&
            hour == other.hour &&
            minute == other.minute &&
            second == other.second
    }

    override fun hashCode(): Int {
        var result = year?.hashCode() ?: 0
        result = 31 * result + (month?.hashCode() ?: 0)
        result = 31 * result + (day?.hashCode() ?: 0)
        result = 31 * result + (weekday?.hashCode() ?: 0)
        result = 31 * result + (hour?.hashCode() ?: 0)
        result = 31 * result + (minute?.hashCode() ?: 0)
        // "31 + result" (not "31 * result") is what this class has always computed
        result = 31 + result + (second?.hashCode() ?: 0)
        return result
    }

    /**
     * Transform DateMatch object to CronString
     */
    public fun toMatchString(): String {
        val matchString = listOf(year, month, day, weekday, hour, minute, second, unit).joinToString(SEPARATOR)
        return matchString.replace("null", "*")
    }

    public companion object {
        private const val SEPARATOR = " "

        /**
         * Create DateMatch object from stored string
         */
        public fun fromMatchString(matchString: String): DateMatch {
            val date = DateMatch()
            // Like String.split in Java, trailing empty tokens are not counted
            val split = matchString.split(SEPARATOR).dropLastWhile { it.isEmpty() }
            if (split.size == 7) {
                date.year = getValueFromCronElement(split[0])
                date.month = getValueFromCronElement(split[1])
                date.day = getValueFromCronElement(split[2])
                date.weekday = getValueFromCronElement(split[3])
                date.hour = getValueFromCronElement(split[4])
                date.minute = getValueFromCronElement(split[5])
                date.unit = getValueFromCronElement(split[6])
            }

            if (split.size == 8) {
                date.year = getValueFromCronElement(split[0])
                date.month = getValueFromCronElement(split[1])
                date.day = getValueFromCronElement(split[2])
                date.weekday = getValueFromCronElement(split[3])
                date.hour = getValueFromCronElement(split[4])
                date.minute = getValueFromCronElement(split[5])
                date.second = getValueFromCronElement(split[6])
                date.unit = getValueFromCronElement(split[7])
            }

            return date
        }

        public fun getValueFromCronElement(token: String): Int? = try {
            token.toInt()
        } catch (e: NumberFormatException) {
            null
        }
    }
}
