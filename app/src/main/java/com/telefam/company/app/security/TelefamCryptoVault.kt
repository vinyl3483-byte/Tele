package com.telefam.company.app.security

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.telefam.company.app.core.TelefamNativeBridge
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

data class DeviceIdentity(
    val deviceFingerprint: String,
    val hardwareAttestationHash: String,
    val deviceName: String,
    val platform: String = "android"
)

/**
 * Hardware-backed Android Keystore AES-256-GCM encryption at rest and Play-compliant
 * hardware/device/IP fingerprint provider with automatic keystore invalidation recovery.
 */
class TelefamCryptoVault(
    private val context: Context
) {
    private val alias = "telefam_master_aes_gcm_v1"
    private val keyStore: KeyStore? by lazy {
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) } }.getOrNull()
    }
    @Volatile
    private var fallbackMemoryKey: SecretKey? = null

    @Synchronized
    private fun getOrCreateKey(forceReset: Boolean = false): SecretKey {
        val ks = keyStore
        if (ks == null) {
            return getOrCreateFallbackKey()
        }
        if (forceReset) {
            runCatching { ks.deleteEntry(alias) }
        } else {
            val existing = runCatching { ks.getKey(alias, null) as? SecretKey }.getOrNull()
            if (existing != null) return existing
        }

        return runCatching {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            val builder = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    builder.setIsStrongBoxBacked(true)
                    generator.init(builder.build())
                    return@runCatching generator.generateKey()
                } catch (_: Exception) {
                    builder.setIsStrongBoxBacked(false)
                }
            }
            generator.init(builder.build())
            generator.generateKey()
        }.getOrElse {
            getOrCreateFallbackKey()
        }
    }

    private fun getOrCreateFallbackKey(): SecretKey {
        fallbackMemoryKey?.let { return it }
        val prefs = context.getSharedPreferences("telefam_key_wrap", Context.MODE_PRIVATE)
        val existing = prefs.getString("fallback_key_b64", null)
        val raw = existing?.let {
            runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull()
        }?.takeIf { it.size == 32 } ?: ByteArray(32).also { bytes ->
            SecureRandom().nextBytes(bytes)
            prefs.edit().putString("fallback_key_b64", Base64.encodeToString(bytes, Base64.NO_WRAP)).apply()
        }
        return SecretKeySpec(raw, "AES").also { fallbackMemoryKey = it }
    }

    fun encryptString(plaintext: String): String {
        val bytes = plaintext.toByteArray(StandardCharsets.UTF_8)
        repeat(2) { attempt ->
            val result = runCatching {
                val key = getOrCreateKey(forceReset = attempt > 0)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key)
                val iv = cipher.iv
                val ciphertext = cipher.doFinal(bytes)
                val packed = ByteArray(1 + iv.size + ciphertext.size)
                packed[0] = iv.size.toByte()
                System.arraycopy(iv, 0, packed, 1, iv.size)
                System.arraycopy(ciphertext, 0, packed, 1 + iv.size, ciphertext.size)
                Base64.encodeToString(packed, Base64.NO_WRAP)
            }
            if (result.isSuccess) return result.getOrThrow()
        }
        // Final fallback using process-safe SecretKeySpec if KeyStore provider threw on both tries
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateFallbackKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(bytes)
        val packed = ByteArray(1 + iv.size + ciphertext.size)
        packed[0] = iv.size.toByte()
        System.arraycopy(iv, 0, packed, 1, iv.size)
        System.arraycopy(ciphertext, 0, packed, 1 + iv.size, ciphertext.size)
        return Base64.encodeToString(packed, Base64.NO_WRAP)
    }

    fun decryptString(encoded: String): String {
        if (encoded.isBlank()) return ""
        val packed = runCatching { Base64.decode(encoded, Base64.NO_WRAP) }.getOrNull() ?: return ""
        if (packed.size < 14) return ""
        val ivLen = packed[0].toInt() and 0xff
        if (ivLen < 12 || ivLen > 16 || 1 + ivLen >= packed.size) return ""
        val iv = packed.copyOfRange(1, 1 + ivLen)
        val ciphertext = packed.copyOfRange(1 + ivLen, packed.size)

        return runCatching {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
        }.getOrElse {
            runCatching {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, getOrCreateFallbackKey(), GCMParameterSpec(128, iv))
                String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8)
            }.getOrDefault("")
        }
    }

    fun deriveNativeMasterKey32(): ByteArray {
        return runCatching {
            val prefs = context.getSharedPreferences("telefam_key_wrap", Context.MODE_PRIVATE)
            val wrapped = prefs.getString("wrapped_core_key", null)
            if (wrapped != null) {
                val decrypted = decryptString(wrapped)
                if (decrypted.isNotEmpty()) {
                    val decoded = runCatching { Base64.decode(decrypted, Base64.NO_WRAP) }.getOrNull()
                    if (decoded != null && decoded.size == 32) return decoded
                }
            }
            val key = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val encoded = Base64.encodeToString(key, Base64.NO_WRAP)
            prefs.edit().putString("wrapped_core_key", encryptString(encoded)).apply()
            key
        }.getOrElse {
            ByteArray(32).also { SecureRandom().nextBytes(it) }
        }
    }

    @SuppressLint("HardwareIds")
    fun buildDeviceIdentity(bridge: TelefamNativeBridge): DeviceIdentity {
        val androidId = runCatching {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        }.getOrNull().orEmpty()

        val deviceDisplayName = runCatching {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
        }.getOrNull()?.takeIf { it.isNotBlank() } ?: "${Build.MANUFACTURER} ${Build.MODEL}"

        val hardwareProfile = listOf(
            Build.MANUFACTURER,
            Build.BRAND,
            Build.MODEL,
            Build.DEVICE,
            Build.BOARD,
            Build.HARDWARE
        ).joinToString(":")

        val hwSecretId = "$androidId:${Build.FINGERPRINT}"
        val fp = bridge.computeDeviceFingerprint(
            platformId = "android",
            hardwareModel = hardwareProfile,
            deviceName = deviceDisplayName,
            hardwareSecretId = hwSecretId
        )
        val attest = bridge.computeDeviceFingerprint(
            platformId = "android-keystore-attest",
            hardwareModel = hardwareProfile,
            deviceName = deviceDisplayName,
            hardwareSecretId = "$alias:$androidId"
        )
        return DeviceIdentity(
            deviceFingerprint = fp,
            hardwareAttestationHash = attest,
            deviceName = deviceDisplayName
        )
    }
}
