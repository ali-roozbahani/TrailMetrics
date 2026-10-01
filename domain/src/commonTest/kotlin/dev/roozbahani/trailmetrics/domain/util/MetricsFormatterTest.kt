package dev.roozbahani.trailmetrics.domain.util

import kotlin.test.Test
import kotlin.test.assertEquals

// Expected strings are worked out by hand from MetricsFormatter's rules, not captured from a run.
// formatFixed (private) is covered through formatDistance and formatSpeed. It uses
// kotlin.math.round, which rounds a tie to the even neighbour.
class MetricsFormatterTest {

    @Test
    fun `formatDistance below 1000 m truncates to whole metres`() {
        assertEquals("0 m", formatDistance(0.0))
        assertEquals("42 m", formatDistance(42.7))
        assertEquals("999 m", formatDistance(999.9))
    }

    @Test
    fun `formatDistance from 1000 m switches to km with two decimals`() {
        assertEquals("1.00 km", formatDistance(1000.0))
        assertEquals("1.50 km", formatDistance(1500.0))
        assertEquals("10.00 km", formatDistance(10_000.0))
    }

    @Test
    fun `formatDistance pads and rounds the km fraction`() {
        // 1.05 km -> scaled 105 -> fraction 5, padded to "05"
        assertEquals("1.05 km", formatDistance(1050.0))
        // 1.004 km -> scaled 100.4 -> 100
        assertEquals("1.00 km", formatDistance(1004.0))
        // 1.999 km -> scaled 199.9 -> 200: the carry reaches the integer part ("2.00", not "1.100")
        assertEquals("2.00 km", formatDistance(1999.0))
    }

    @Test
    fun `formatElapsedTime zero pads minutes and seconds`() {
        assertEquals("00:00", formatElapsedTime(0))
        assertEquals("00:01", formatElapsedTime(1_000))
        assertEquals("00:59", formatElapsedTime(59_000))
        assertEquals("01:00", formatElapsedTime(60_000))
        assertEquals("01:01", formatElapsedTime(61_000))
        assertEquals("59:59", formatElapsedTime(3_599_000))
    }

    @Test
    fun `formatElapsedTime drops sub-second millis`() {
        assertEquals("00:00", formatElapsedTime(999))
        assertEquals("00:59", formatElapsedTime(59_999))
    }

    @Test
    fun `formatElapsedTime does not wrap minutes into hours`() {
        // Confirmed product decision: elapsed time is always shown as minutes:seconds, so an hour or
        // more keeps counting minutes ("90:00", "100:00") instead of switching to h:mm:ss.
        assertEquals("60:00", formatElapsedTime(60 * 60_000L))
        assertEquals("90:00", formatElapsedTime(90 * 60_000L))
        assertEquals("100:00", formatElapsedTime(100 * 60_000L))
        assertEquals("100:05", formatElapsedTime(100 * 60_000L + 5_000))
    }

    @Test
    fun `formatSpeed shows placeholder when speed is unknown`() {
        assertEquals("-- km/h", formatSpeed(null))
    }

    @Test
    fun `formatSpeed converts metres per second to km per hour with one decimal`() {
        assertEquals("0.0 km/h", formatSpeed(0f))
        // 1 m/s * 3.6 = 3.6 km/h
        assertEquals("3.6 km/h", formatSpeed(1f))
        // 2.5 m/s * 3.6 = 9.0 km/h
        assertEquals("9.0 km/h", formatSpeed(2.5f))
        // 10 m/s * 3.6 = 36.0 km/h
        assertEquals("36.0 km/h", formatSpeed(10f))
        // 2.7666667 m/s * 3.6 = 9.96 km/h -> scaled 99.6 -> 100: carries into the integer part
        assertEquals("10.0 km/h", formatSpeed(2.7666667f))
    }

    @Test
    fun `formatSpeed rounds a tie to the even tenth`() {
        // 0.125 m/s = 0.45 km/h -> scaled 4.5 -> 4 (half to even), not 5
        assertEquals("0.4 km/h", formatSpeed(0.125f))
        // 0.625 m/s = 2.25 km/h -> scaled 22.5 -> 22 (half to even), not 23
        assertEquals("2.2 km/h", formatSpeed(0.625f))
    }

    @Test
    fun `formatSpeed keeps the sign of negative values`() {
        // -2.5 m/s = -9.0 km/h
        assertEquals("-9.0 km/h", formatSpeed(-2.5f))
        // -0.125 m/s = -0.45 km/h -> scaled -4.5 -> -4: sign kept although the integer part is 0
        assertEquals("-0.4 km/h", formatSpeed(-0.125f))
    }

    @Test
    fun `formatSpeed does not show a negative zero`() {
        // -0.01 m/s = -0.036 km/h -> scaled -0.36 -> rounds to 0, so no minus sign
        assertEquals("0.0 km/h", formatSpeed(-0.01f))
    }

    @Test
    fun `formatCalories shows placeholder when calories are unknown`() {
        assertEquals("-- kcal", formatCalories(null))
    }

    @Test
    fun `formatCalories rounds to the nearest whole kcal`() {
        assertEquals("0 kcal", formatCalories(0.0))
        assertEquals("0 kcal", formatCalories(0.4))
        assertEquals("123 kcal", formatCalories(123.4))
        assertEquals("124 kcal", formatCalories(123.6))
        // roundToInt rounds a tie up (towards positive infinity), unlike formatFixed's half to even
        assertEquals("123 kcal", formatCalories(122.5))
        assertEquals("124 kcal", formatCalories(123.5))
    }
}
