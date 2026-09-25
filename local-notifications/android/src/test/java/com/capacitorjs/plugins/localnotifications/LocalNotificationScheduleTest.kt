package com.capacitorjs.plugins.localnotifications

import java.text.ParseException
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class LocalNotificationScheduleTest {
    private val defaultLocale = Locale.getDefault()

    @After
    fun tearDown() {
        Locale.setDefault(defaultLocale)
    }

    @Test
    fun atIsReadInTheGregorianCalendarInAnyLocale() {
        // th-TH counts years in the Buddhist era, ar-EG writes Arabic-Indic digits, and the Japanese calendar counts
        // years from the start of the current era.
        for (tag in listOf("en-US", "th-TH", "ar-EG", "ja-JP-u-ca-japanese")) {
            Locale.setDefault(Locale.forLanguageTag(tag))

            // 2026-09-26T10:00:00Z
            assertEquals(tag, 1_790_416_800_000L, LocalNotificationSchedule.parseJsDate("2026-09-26T10:00:00.000Z").time)
        }
    }

    @Test
    fun anotherFormatIsAParseException() {
        assertThrows(ParseException::class.java) { LocalNotificationSchedule.parseJsDate("26/09/2026") }
    }
}
