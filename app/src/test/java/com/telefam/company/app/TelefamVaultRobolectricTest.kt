package com.telefam.company.app

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.telefam.company.app.security.TelefamCryptoVault
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class TelefamVaultRobolectricTest {

    private fun newVault(): TelefamCryptoVault {
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        return TelefamCryptoVault(ctx)
    }

    @Test
    fun decryptString_handlesEmptyAndCorruptInputsWithoutCrashing() {
        val vault = newVault()
        assertEquals("", vault.decryptString(""))
        assertEquals("", vault.decryptString("   "))
        assertEquals("", vault.decryptString("not-valid-base64!!!@@@"))
        assertEquals("", vault.decryptString("AAAA"))
        // IV length byte = 99 (out of 12..16 bounds)
        assertEquals("", vault.decryptString("YwAAAAAAAAAAAAAAAAAAAAAAAA=="))
    }

    @Test
    fun encryptAndDecrypt_roundTripsAndDerives32ByteKey() {
        val vault = newVault()
        val encrypted = vault.encryptString("telefam-session-secret")
        assertTrue(encrypted.isNotBlank())
        assertEquals("telefam-session-secret", vault.decryptString(encrypted))

        val key = vault.deriveNativeMasterKey32()
        assertEquals(32, key.size)
    }
}
