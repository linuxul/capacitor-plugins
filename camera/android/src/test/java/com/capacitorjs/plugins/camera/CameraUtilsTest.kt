package com.capacitorjs.plugins.camera

import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class CameraUtilsTest {
    private val defaultLocale = Locale.getDefault()
    private val defaultTimeZone = TimeZone.getDefault()

    @Before
    fun setUp() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    @After
    fun tearDown() {
        Locale.setDefault(defaultLocale)
        TimeZone.setDefault(defaultTimeZone)
    }

    @Test
    fun fileTimestampUsesGregorianYearsAndAsciiDigitsInAnyLocale() {
        // 2026-09-26T10:20:30Z
        val date = Date(1_790_418_030_000L)

        // th-TH counts years in the Buddhist era, ar-EG writes Arabic-Indic digits, and the Japanese calendar counts
        // years from the start of the current era.
        for (tag in listOf("en-US", "th-TH", "ar-EG", "ja-JP-u-ca-japanese")) {
            Locale.setDefault(Locale.forLanguageTag(tag))

            assertEquals(tag, "20260926_102030", CameraUtils.fileTimestamp(date))
        }
    }
}
