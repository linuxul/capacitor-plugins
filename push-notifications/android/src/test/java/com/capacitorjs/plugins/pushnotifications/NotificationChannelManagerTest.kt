package com.capacitorjs.plugins.pushnotifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * The channel light color, which the TypeScript definition documents as `#RRGGBB` or `#RRGGBBAA`. The
 * local-notifications and push-notifications plugins run this same test.
 */
class NotificationChannelManagerTest {
    @Test
    fun rgbIsOpaque() {
        assertEquals(0xFF336699.toInt(), parseLightColor("#336699"))
        assertEquals(0xFF336699.toInt(), parseLightColor("336699"))
        assertEquals(0xFFABCDEF.toInt(), parseLightColor("#abcdef"))
    }

    @Test
    fun rgbaEndsWithTheAlpha() {
        // Color.parseColor reads eight digits as #AARRGGBB, which gave this color the alpha 0x33 and the blue 0x80
        assertEquals(0x80336699.toInt(), parseLightColor("#33669980"))
        assertEquals(0x00336699, parseLightColor("33669900"))
    }

    @Test
    fun otherValuesAreInvalid() {
        for (value in listOf("", "#", "#fff", "#12345", "#1234567", "#1234567890", "##336699", "red", "#GG0000", "#-12345", "#+12345")) {
            assertThrows(value, IllegalArgumentException::class.java) { parseLightColor(value) }
        }
    }
}
