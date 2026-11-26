package com.telefam.company.app

import com.telefam.company.app.core.NetworkQuality
import com.telefam.company.app.core.TelefamNativeBridge
import com.telefam.company.app.feed.FeedAspectRatioMath
import com.telefam.company.app.feed.FeedFormatter
import com.telefam.company.app.feed.FeedReportReason
import com.telefam.company.app.feed.FeedVideoVisibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelefamCoreUnitTest {

    private val bridge = TelefamNativeBridge(
        vaultPath = "",
        masterKey32 = ByteArray(32) { 0x42 }
    )

    @Test
    fun emailValidation_acceptsValidAndRejectsInvalid() {
        assertTrue(bridge.validateEmail("user@telefam.app"))
        assertFalse(bridge.validateEmail("bad-email"))
        assertFalse(bridge.validateEmail("a@b"))
        assertFalse(bridge.validateEmail("user @telefam.app"))
    }

    @Test
    fun otpValidation_requiresSixDigits() {
        assertTrue(bridge.validateOtp("123456"))
        assertFalse(bridge.validateOtp("12345"))
        assertFalse(bridge.validateOtp("12345a"))
    }

    @Test
    fun cooldownSchedule_matches1m3xThen15mThen1hThen24h() {
        assertEquals(60L, TelefamNativeBridge.cooldownDurationForCount(1).first)
        assertEquals(60L, TelefamNativeBridge.cooldownDurationForCount(2).first)
        assertEquals(60L, TelefamNativeBridge.cooldownDurationForCount(3).first)
        assertEquals(900L, TelefamNativeBridge.cooldownDurationForCount(4).first)
        assertEquals(3600L, TelefamNativeBridge.cooldownDurationForCount(5).first)
        assertEquals(86400L, TelefamNativeBridge.cooldownDurationForCount(6).first)
    }

    @Test
    fun errorSanitizer_returnsExpectedCleanMessages() {
        assertEquals("No internet", bridge.sanitizeError(0, "timeout"))
        val msg500 = bridge.sanitizeError(500, "pq: relation users violates rls")
        assertEquals("Error has occurred, try again later", msg500)
        assertFalse(msg500.contains("pq"))
        assertFalse(msg500.contains("rls"))
    }

    @Test
    fun ageValidation_enforcesThirteenYearsAndAboveOnly() {
        assertTrue(bridge.validateAge13Plus(2013, 11, 24, 2026, 11, 24))
        assertFalse(bridge.validateAge13Plus(2013, 11, 25, 2026, 11, 24))
        assertFalse(bridge.validateAge13Plus(2014, 1, 1, 2026, 11, 24))
    }

    @Test
    fun phoneValidation_checksCountryFormat() {
        assertTrue(bridge.validatePhoneNumber("KE", "0712345678"))
        assertTrue(bridge.validatePhoneNumber("KE", "712345678"))
        assertFalse(bridge.validatePhoneNumber("KE", "12345"))
        assertTrue(bridge.validatePhoneNumber("US", "4155550199"))
        assertFalse(bridge.validatePhoneNumber("US", "415555"))
    }

    @Test
    fun countrySuggestion_prefersCarrierThenTimezoneThenLocale() {
        assertEquals("KE", bridge.suggestCountryIso("ke", "America/New_York", "US"))
        assertEquals("KE", bridge.suggestCountryIso("", "Africa/Nairobi", "US"))
        assertEquals("GB", bridge.suggestCountryIso("", "Europe/London", "US"))
        assertEquals("US", bridge.suggestCountryIso("", "Unknown/Zone", "us"))
    }

    @Test
    fun emailAutofill_extractsFullNameAndUsername() {
        val (fullName, username) = bridge.autofillProfileFromEmail("jane.doe-99@telefam.app")
        assertEquals("Jane Doe 99", fullName)
        assertEquals("jane_doe_99", username)
    }

    @Test
    fun adaptiveSync_batchesOnlineAndDefersOffline() {
        assertEquals(25, bridge.adaptiveBatchSize(NetworkQuality.ONLINE))
        assertEquals(0, bridge.adaptiveBatchSize(NetworkQuality.OFFLINE))
    }

    @Test
    fun followRateLimit_allowsFiftyPerMinuteThenBlocksUntilWindowExpires() {
        val baseSec = 1_760_000_000L
        repeat(50) { idx ->
            assertTrue(
                "Expected action #$idx to be allowed",
                bridge.allowFollowRateLimit("user-1", baseSec)
            )
        }
        assertFalse(bridge.allowFollowRateLimit("user-1", baseSec + 10))
        assertTrue(bridge.allowFollowRateLimit("user-1", baseSec + 61))
    }

    @Test
    fun relationshipComputation_coversAllFourStates() {
        assertEquals("follow", bridge.computeRelationship(isFollowing = false, followsMe = false))
        assertEquals("follow_back", bridge.computeRelationship(isFollowing = false, followsMe = true))
        assertEquals("following", bridge.computeRelationship(isFollowing = true, followsMe = false))
        assertEquals("friends", bridge.computeRelationship(isFollowing = true, followsMe = true))
    }

    @Test
    fun frameDHash_produces16HexCharsAndIsGradientSensitive() {
        val w = 36
        val h = 16
        val leftBright = ByteArray(w * h * 4)
        val rightBright = ByteArray(w * h * 4)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val idx = (y * w + x) * 4
                val vLeft = (255 - (x * 255 / w)).toByte()
                val vRight = (x * 255 / w).toByte()
                leftBright[idx] = vLeft; leftBright[idx + 1] = vLeft; leftBright[idx + 2] = vLeft; leftBright[idx + 3] = -1
                rightBright[idx] = vRight; rightBright[idx + 1] = vRight; rightBright[idx + 2] = vRight; rightBright[idx + 3] = -1
            }
        }
        val hashLeft = bridge.computeFrameDHash(leftBright, w, h)
        val hashRight = bridge.computeFrameDHash(rightBright, w, h)
        assertEquals(16, hashLeft.length)
        assertEquals(16, hashRight.length)
        assertEquals("ffffffffffffffff", hashLeft)
        assertEquals("0000000000000000", hashRight)
    }

    @Test
    fun mediaContentId_isDeterministicSha256Hex() {
        val cid1 = bridge.computeMediaContentId("video", "abcd0123abcd0123,ff00ff00ff00ff00", "deadbeef", 1920, 1080, 12000L)
        val cid2 = bridge.computeMediaContentId("video", "abcd0123abcd0123,ff00ff00ff00ff00", "deadbeef", 1920, 1080, 12000L)
        val cidDifferent = bridge.computeMediaContentId("video", "abcd0123abcd0123,ff00ff00ff00ff01", "deadbeef", 1920, 1080, 12000L)
        assertEquals(64, cid1.length)
        assertEquals(cid1, cid2)
        assertFalse(cid1 == cidDifferent)
    }

    @Test
    fun feedAspectRatioMath_preservesOriginalRatiosAndTriggersAmbientBackdrop() {
        val containerW = 1080f
        val containerH = 1920f

        val portrait = FeedAspectRatioMath.computeFittedSize(containerW, containerH, 1080, 1920, 0.5625)
        assertEquals(1080f, portrait.widthPx, 1f)
        assertEquals(1920f, portrait.heightPx, 1f)
        assertFalse(portrait.needsAmbientBackdrop)

        val landscape = FeedAspectRatioMath.computeFittedSize(containerW, containerH, 1920, 1080, 1.777)
        assertEquals(1080f, landscape.widthPx, 1f)
        assertEquals(607.5f, landscape.heightPx, 1f)
        assertTrue(landscape.needsAmbientBackdrop)

        val square = FeedAspectRatioMath.computeFittedSize(containerW, containerH, 1080, 1080, 1.0)
        assertEquals(1080f, square.widthPx, 1f)
        assertEquals(1080f, square.heightPx, 1f)
        assertTrue(square.needsAmbientBackdrop)

        val ultrawide = FeedAspectRatioMath.computeFittedSize(containerW, containerH, 2560, 1080, 2.37)
        assertEquals(1080f, ultrawide.widthPx, 1f)
        assertTrue(ultrawide.heightPx < 500f)
        assertTrue(ultrawide.needsAmbientBackdrop)
    }

    @Test
    fun feedFormatter_formatsCountsAndExtractsHashtagsAndUrls() {
        assertEquals("999", FeedFormatter.formatCount(999L))
        assertEquals("128.4K", FeedFormatter.formatCount(128_450L))
        assertEquals("2.1M", FeedFormatter.formatCount(2_140_000L))
        assertEquals(listOf("nightvibes", "citylights"), FeedFormatter.extractHashtags("City #NightVibes ❤️ #citylights https://telefam.app/v/1"))
        assertEquals(listOf("https://telefam.app/v/1"), FeedFormatter.extractUrls("Check https://telefam.app/v/1 #explore"))
        assertEquals(8, FeedReportReason.entries.size)
        assertEquals(FeedVideoVisibility.PRIVATE, FeedVideoVisibility.fromApi("private"))
    }
}
