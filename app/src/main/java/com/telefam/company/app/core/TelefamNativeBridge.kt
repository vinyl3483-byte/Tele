package com.telefam.company.app.core

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.min

enum class NetworkQuality(val code: Int) {
    ONLINE(0),
    OFFLINE(1)
}

data class CooldownState(
    val remainingSeconds: Long,
    val tierIndex: Int,
    val resendCount: Int,
    val canResend: Boolean
)

class TelefamNativeBridge(
    vaultPath: String,
    masterKey32: ByteArray
) {
    private val nativeLoaded: Boolean
    private var nativeHandle: Long = 0L
    private val rateBuckets = ConcurrentHashMap<String, ArrayDeque<Long>>()

    init {
        var loaded = false
        try {
            System.loadLibrary("telefam_core_jni")
            loaded = true
        } catch (_: UnsatisfiedLinkError) {
            loaded = false
        }
        nativeLoaded = loaded
        if (nativeLoaded && masterKey32.size == 32) {
            nativeHandle = nativeCreateEngine(vaultPath, masterKey32)
        }
    }

    fun destroy() {
        if (nativeLoaded && nativeHandle != 0L) {
            nativeDestroyEngine(nativeHandle)
            nativeHandle = 0L
        }
    }

    fun computeDeviceFingerprint(
        platformId: String,
        hardwareModel: String,
        deviceName: String,
        hardwareSecretId: String,
        salt: String = "telefam-android-fp-v1"
    ): String {
        if (nativeLoaded) {
            return nativeDeviceFingerprint(platformId, hardwareModel, deviceName, hardwareSecretId, salt)
        }
        return hmacSha256Hex(salt, "$platformId|$hardwareModel|$deviceName|$hardwareSecretId")
    }

    fun computeIpFingerprint(
        observedIp: String,
        subnetPrefix: String,
        salt: String = "telefam-android-ip-v1"
    ): String {
        if (nativeLoaded) {
            return nativeIpFingerprint(observedIp, subnetPrefix, salt)
        }
        return hmacSha256Hex(salt, "$observedIp|$subnetPrefix")
    }

    fun validateEmail(email: String): Boolean {
        if (nativeLoaded) return nativeValidateEmail(email)
        val s = email.trim()
        if (s.length !in 5..254) return false
        val at = s.indexOf('@')
        if (at <= 0 || at == s.length - 1 || s.indexOf('@', at + 1) != -1) return false
        val dot = s.indexOf('.', at + 1)
        if (dot <= at + 1 || dot == s.length - 1) return false
        return s.none { it.isWhitespace() || it.code < 33 || it.code > 126 }
    }

    fun validateOtp(otp: String): Boolean {
        if (nativeLoaded) return nativeValidateOtp(otp)
        return otp.length == 6 && otp.all { it.isDigit() }
    }

    fun validateAge13Plus(
        birthYear: Int,
        birthMonth: Int,
        birthDay: Int,
        nowYear: Int,
        nowMonth: Int,
        nowDay: Int
    ): Boolean {
        if (nativeLoaded) {
            return nativeValidateAge13Plus(birthYear, birthMonth, birthDay, nowYear, nowMonth, nowDay)
        }
        if (birthYear < 1900 || birthMonth !in 1..12 || birthDay !in 1..31) return false
        var age = nowYear - birthYear
        if (nowMonth < birthMonth || (nowMonth == birthMonth && nowDay < birthDay)) {
            age -= 1
        }
        return age >= 13
    }

    fun validatePhoneNumber(countryIso: String, nationalNumber: String): Boolean {
        if (nativeLoaded) return nativeValidatePhone(countryIso, nationalNumber)
        val cleaned = nationalNumber.trim()
        if (cleaned.any { !it.isDigit() && it != ' ' && it != '-' && it != '(' && it != ')' }) {
            return false
        }
        var digits = cleaned.filter { it.isDigit() }
        if (digits.length > 6 && digits.startsWith("0")) {
            digits = digits.drop(1)
        }
        val range = PHONE_RULES[countryIso.uppercase()] ?: (7..15)
        return digits.length in range
    }

    fun suggestCountryIso(carrierIso: String, timezoneId: String, localeIso: String): String {
        if (nativeLoaded) return nativeSuggestCountryIso(carrierIso, timezoneId, localeIso)
        val carrier = carrierIso.trim().uppercase()
        if (carrier.length == 2 && carrier.all { it in 'A'..'Z' }) return carrier
        TZ_TO_COUNTRY.entries.firstOrNull { timezoneId.contains(it.key, ignoreCase = true) }?.let {
            return it.value
        }
        val loc = localeIso.trim().uppercase()
        if (loc.length == 2 && loc.all { it in 'A'..'Z' }) return loc
        return "KE"
    }

    fun autofillProfileFromEmail(email: String): Pair<String, String> {
        if (nativeLoaded) {
            val res = nativeAutofillFromEmail(email)
            if (res.size == 2) return res[0] to res[1]
        }
        val prefix = email.substringBefore('@').trim()
        val fullName = prefix
            .split('.', '_', '-')
            .filter { it.isNotBlank() }
            .joinToString(" ") { part ->
                part.filter { it.isLetterOrDigit() }
                    .replaceFirstChar { ch -> if (ch.isLowerCase()) ch.titlecase() else ch.toString() }
            }
        val username = prefix
            .lowercase()
            .replace('.', '_')
            .replace('-', '_')
            .filter { it.isLetterOrDigit() || it == '_' }
            .trim('_')
            .take(30)
        return fullName to username
    }

    fun sanitizeError(httpStatus: Int, rawError: String? = null): String {
        if (nativeLoaded) return nativeSanitizeError(httpStatus, rawError ?: "")
        return if (httpStatus == 0) {
            "No internet"
        } else {
            "Error has occurred, try again later"
        }
    }

    fun allowRateLimit(accountKey: String, deviceFp: String, ipFp: String, nowSec: Long): Boolean {
        if (nativeLoaded && nativeHandle != 0L) {
            return nativeAllowRateLimit(nativeHandle, accountKey, deviceFp, ipFp, nowSec)
        }
        if (accountKey.isNotBlank() && !checkBucket("acc:${accountKey.lowercase()}", nowSec, 10, 60)) return false
        if (deviceFp.isNotBlank() && !checkBucket("dev:$deviceFp", nowSec, 30, 60)) return false
        if (ipFp.isNotBlank() && !checkBucket("ip:$ipFp", nowSec, 45, 60)) return false
        return true
    }

    fun allowFollowRateLimit(accountKey: String, nowSec: Long): Boolean {
        if (nativeLoaded && nativeHandle != 0L) {
            return nativeAllowFollowRateLimit(nativeHandle, accountKey, nowSec)
        }
        if (accountKey.isBlank()) return false
        return checkBucket("follow:${accountKey.lowercase()}", nowSec, 50, 60)
    }

    fun computeRelationship(isFollowing: Boolean, followsMe: Boolean): String {
        val code = if (nativeLoaded) {
            nativeRelationshipState(isFollowing, followsMe)
        } else {
            when {
                isFollowing && followsMe -> 3
                isFollowing -> 2
                followsMe -> 1
                else -> 0
            }
        }
        return when (code) {
            3 -> "friends"
            2 -> "following"
            1 -> "follow_back"
            else -> "follow"
        }
    }

    fun adaptiveBatchSize(quality: NetworkQuality): Int =
        if (quality == NetworkQuality.ONLINE) 25 else 0

    fun retryBackoffMs(attempt: Int, quality: NetworkQuality): Long {
        if (quality == NetworkQuality.OFFLINE) return 5000L
        val clamped = attempt.coerceIn(0, 6)
        return min(30_000L, 750L * (1L shl clamped))
    }

    fun computeFrameDHash(rgbaPixels: ByteArray, width: Int, height: Int): String {
        if (width <= 0 || height <= 0 || rgbaPixels.size < width * height * 4) return ""
        if (nativeLoaded) {
            return nativeComputeFrameDHash(rgbaPixels, width, height)
        }
        val grid = LongArray(72)
        for (gy in 0 until 8) {
            val yStart = (gy * height) / 8
            val yEnd = maxOf(yStart + 1, ((gy + 1) * height) / 8)
            for (gx in 0 until 9) {
                val xStart = (gx * width) / 9
                val xEnd = maxOf(xStart + 1, ((gx + 1) * width) / 9)
                var sum = 0L
                var count = 0L
                for (y in yStart until yEnd) {
                    val rowBase = y * width
                    for (x in xStart until xEnd) {
                        val idx = (rowBase + x) * 4
                        val r = rgbaPixels[idx].toInt() and 0xFF
                        val g = rgbaPixels[idx + 1].toInt() and 0xFF
                        val b = rgbaPixels[idx + 2].toInt() and 0xFF
                        sum += (299L * r + 587L * g + 114L * b) / 1000L
                        count++
                    }
                }
                grid[gy * 9 + gx] = if (count > 0) sum / count else 0L
            }
        }
        var bits = 0UL
        for (gy in 0 until 8) {
            for (gx in 0 until 8) {
                val bitIndex = gy * 8 + gx
                if (grid[gy * 9 + gx] > grid[gy * 9 + gx + 1]) {
                    bits = bits or (1UL shl (63 - bitIndex))
                }
            }
        }
        return bits.toString(16).padStart(16, '0')
    }

    fun computeMediaContentId(
        mediaKind: String,
        frameHashesCsv: String,
        audioFpHex: String,
        width: Int,
        height: Int,
        durationMs: Long,
        salt: String = "telefam-content-id-v1"
    ): String {
        if (nativeLoaded) {
            return nativeComputeMediaContentId(
                mediaKind, frameHashesCsv, audioFpHex, width, height, durationMs, salt
            )
        }
        return hmacSha256Hex(
            salt,
            "$mediaKind|$width|$height|$durationMs|$frameHashesCsv|$audioFpHex"
        )
    }

    companion object {
        private val PHONE_RULES = mapOf(
            "KE" to (9..10),
            "US" to (10..10),
            "CA" to (10..10),
            "GB" to (10..10),
            "NG" to (10..10),
            "ZA" to (9..9),
            "TZ" to (9..9),
            "UG" to (9..9),
            "RW" to (9..9),
            "ET" to (9..9),
            "IN" to (10..10),
            "DE" to (10..11),
            "FR" to (9..9),
            "AE" to (9..9),
            "AU" to (9..9),
            "JP" to (10..10),
            "BR" to (10..11)
        )

        private val TZ_TO_COUNTRY = mapOf(
            "Nairobi" to "KE",
            "Lagos" to "NG",
            "Johannesburg" to "ZA",
            "Dar_es_Salaam" to "TZ",
            "Kampala" to "UG",
            "Kigali" to "RW",
            "Addis_Ababa" to "ET",
            "London" to "GB",
            "New_York" to "US",
            "Chicago" to "US",
            "Denver" to "US",
            "Los_Angeles" to "US",
            "Toronto" to "CA",
            "Vancouver" to "CA",
            "Kolkata" to "IN",
            "Calcutta" to "IN",
            "Berlin" to "DE",
            "Paris" to "FR",
            "Dubai" to "AE",
            "Sydney" to "AU",
            "Tokyo" to "JP",
            "Sao_Paulo" to "BR"
        )

        fun cooldownDurationForCount(countOneBased: Int): Pair<Long, Int> = when {
            countOneBased <= 3 -> 60L to 1
            countOneBased == 4 -> 15L * 60L to 2
            countOneBased == 5 -> 60L * 60L to 3
            else -> 24L * 60L * 60L to 4
        }

        fun sha256Hex(input: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(input.toByteArray(StandardCharsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        fun hmacSha256Hex(secret: String, data: String): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(StandardCharsets.UTF_8), "HmacSHA256"))
            val bytes = mac.doFinal(data.toByteArray(StandardCharsets.UTF_8))
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }

    @Synchronized
    private fun checkBucket(key: String, nowSec: Long, maxReq: Int, windowSec: Long): Boolean {
        val q = rateBuckets.getOrPut(key) { ArrayDeque() }
        while (q.isNotEmpty() && (nowSec - q.first()) >= windowSec) {
            q.removeFirst()
        }
        if (q.size >= maxReq) return false
        q.addLast(nowSec)
        return true
    }

    private external fun nativeCreateEngine(vaultPath: String, masterKey32: ByteArray): Long
    private external fun nativeDestroyEngine(handle: Long)
    private external fun nativeDeviceFingerprint(platform: String, model: String, deviceName: String, hwId: String, salt: String): String
    private external fun nativeIpFingerprint(ip: String, subnet: String, salt: String): String
    private external fun nativeValidateEmail(email: String): Boolean
    private external fun nativeValidateOtp(otp: String): Boolean
    private external fun nativeValidateAge13Plus(by: Int, bm: Int, bd: Int, ny: Int, nm: Int, nd: Int): Boolean
    private external fun nativeValidatePhone(countryIso: String, phone: String): Boolean
    private external fun nativeSuggestCountryIso(carrierIso: String, tzId: String, localeIso: String): String
    private external fun nativeAutofillFromEmail(email: String): Array<String>
    private external fun nativeSanitizeError(httpStatus: Int, rawError: String): String
    private external fun nativeAllowRateLimit(handle: Long, acc: String, devFp: String, ipFp: String, nowSec: Long): Boolean
    private external fun nativeAllowFollowRateLimit(handle: Long, accountKey: String, nowSec: Long): Boolean
    private external fun nativeRelationshipState(isFollowing: Boolean, followsMe: Boolean): Int
    private external fun nativeComputeFrameDHash(rgbaPixels: ByteArray, width: Int, height: Int): String
    private external fun nativeComputeMediaContentId(
        mediaKind: String,
        frameHashesCsv: String,
        audioFpHex: String,
        width: Int,
        height: Int,
        durationMs: Long,
        salt: String
    ): String
}
