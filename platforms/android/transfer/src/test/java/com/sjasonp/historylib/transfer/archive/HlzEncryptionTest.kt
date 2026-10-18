package com.sjasonp.historylib.transfer.archive

import com.goterl.lazysodium.SodiumJava
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.random.Random

class HlzEncryptionTest {
    @Before
    fun useDesktopLibsodium() {
        HlzEncryption.setSodiumForTesting(SodiumJava())
    }

    @Test
    fun roundTripsSmallPlaintext() {
        val plaintext = "hello historylib".toByteArray()
        val encrypted = HlzEncryption.encrypt(plaintext, "correct horse battery staple".toCharArray())
        assertArrayEquals(plaintext, HlzEncryption.decrypt(encrypted, "correct horse battery staple".toCharArray()))
    }

    @Test
    fun roundTripsMultiChunkPlaintext() {
        val plaintext = ByteArray(2_200_000) { Random.nextInt(256).toByte() }
        val password = "a long enough password".toCharArray()
        val encrypted = HlzEncryption.encrypt(plaintext, password)
        assertArrayEquals(plaintext, HlzEncryption.decrypt(encrypted, password))
    }

    @Test
    fun encryptionIsRandomized() {
        val plaintext = "same input".toByteArray()
        val a = HlzEncryption.encrypt(plaintext, "password password".toCharArray())
        val b = HlzEncryption.encrypt(plaintext, "password password".toCharArray())
        assertFalse(a.contentEquals(b))
    }

    @Test
    fun streamsDecryptToWithoutLoadingWholeCiphertext() {
        val plaintext = ByteArray(2_500_000) { Random.nextInt(256).toByte() }
        val password = "streaming password".toCharArray()
        val ciphertext = ByteArrayOutputStream().also { out ->
            HlzEncryption.encryptingOutputStream(out, password).use { it.write(plaintext) }
        }.toByteArray()
        val decrypted = ByteArrayOutputStream()
        HlzEncryption.decryptTo(ByteArrayInputStream(ciphertext), decrypted, password)
        assertArrayEquals(plaintext, decrypted.toByteArray())
    }

    @Test
    fun rejectsOversizedFrameBeforeAllocation() {
        val password = "bounded frame password".toCharArray()
        val encrypted = HlzEncryption.encrypt("x".toByteArray(), password)
        encrypted[66] = 0x7f
        encrypted[67] = 0xff.toByte()
        encrypted[68] = 0xff.toByte()
        encrypted[69] = 0xff.toByte()

        assertThrows(HlzEncryptionException::class.java) {
            HlzEncryption.decrypt(encrypted, password)
        }
    }
}
