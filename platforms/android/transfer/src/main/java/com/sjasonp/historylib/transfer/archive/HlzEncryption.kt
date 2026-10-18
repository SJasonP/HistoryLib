package com.sjasonp.historylib.transfer.archive

import com.goterl.lazysodium.SodiumAndroid
import com.goterl.lazysodium.Sodium
import com.goterl.lazysodium.interfaces.PwHash
import com.sun.jna.NativeLong
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.FilterOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom
import java.text.Normalizer

/**
 * HLZENC v1 container per shared/specs/hlz-v1.md. The inner plaintext is a
 * regular ZIP; this object only authenticates and encrypts/decrypts the bytes.
 *
 * The implementation uses libsodium: Argon2id for key derivation and
 * XChaCha20-Poly1305 (IETF) AEAD for every secretstream-style frame. The full
 * 66-byte fixed header is authenticated as additional data for each frame.
 */
object HlzEncryption {
    private const val KDF_ARGON2ID = 0x02
    private const val CIPHER_XCHACHA20_POLY1305_SECRETSTREAM = 0x03
    private const val OPERATIONS_LIMIT = 2
    private const val MEMORY_LIMIT_BYTES = 64L * 1024L * 1024L
    private const val CHUNK_SIZE_BYTES = 1_048_576
    private const val KEY_BYTES = 32
    private const val SALT_BYTES = 16
    private const val HEADER_BYTES = 24
    private const val TAG_BYTES = 16
    private const val TAG_MESSAGE: Byte = 0x00
    private const val TAG_FINAL: Byte = 0x03
    private const val MAX_FRAME_BYTES = 1 + CHUNK_SIZE_BYTES + TAG_BYTES

    private val magic = byteArrayOf(
        'H'.code.toByte(),
        'L'.code.toByte(),
        'Z'.code.toByte(),
        'E'.code.toByte(),
        'N'.code.toByte(),
        'C'.code.toByte(),
        0x00,
        0x31,
    )

    private val random = SecureRandom()
    private var sodiumOverride: Sodium? = null
    private var cachedSodium: Sodium? = null

    private val sodium: Sodium
        get() {
            sodiumOverride?.let { return it }
            return cachedSodium ?: SodiumAndroid().also { cachedSodium = it }
        }

    internal fun setSodiumForTesting(value: Sodium) {
        sodiumOverride = value
    }

    fun encrypt(plaintext: ByteArray, password: CharArray): ByteArray {
        val output = ByteArrayOutputStream()
        encryptingOutputStream(output, password).use { stream ->
            stream.write(plaintext)
        }
        return output.toByteArray()
    }

    fun encryptingOutputStream(out: OutputStream, password: CharArray): OutputStream {
        return HlzEncryptingOutputStream(out, password)
    }

    fun decryptTo(encrypted: InputStream, out: OutputStream, password: CharArray) {
        val header = ByteArray(66)
        if (!readFullyOrEof(encrypted, header) || header.size != 66) {
            throw HlzEncryptionException("Truncated HLZENC header")
        }
        validateHeader(header)
        val salt = header.copyOfRange(26, 42)
        val nonce = header.copyOfRange(42, 66)
        val key = deriveKey(normalizePassword(password), salt)

        var sawFinal = false
        while (true) {
            val lengthBytes = ByteArray(4)
            val lengthRead = readUpTo(encrypted, lengthBytes)
            if (lengthRead == 0) break
            if (lengthRead != 4) throw HlzEncryptionException("Truncated frame length")
            val encodedFrameLength = readU32(lengthBytes, 0)
            if (encodedFrameLength !in (TAG_BYTES + 1).toLong()..MAX_FRAME_BYTES.toLong()) {
                throw HlzEncryptionException("Invalid frame length")
            }
            val frameLength = encodedFrameLength.toInt()
            val frame = ByteArray(frameLength)
            if (!readFullyOrEof(encrypted, frame)) throw HlzEncryptionException("Truncated frame")
            val (tag, plain) = decryptFrame(key, nonce, header, frame)
            out.write(plain)
            if (tag == TAG_FINAL) {
                sawFinal = true
                break
            }
            if (tag != TAG_MESSAGE) throw HlzEncryptionException("Unsupported frame tag")
            incrementNonce(nonce)
        }
        if (!sawFinal) throw HlzEncryptionException("Missing FINAL frame")
        if (encrypted.read() != -1) throw HlzEncryptionException("Trailing bytes after FINAL frame")
    }

    fun decrypt(encrypted: ByteArray, password: CharArray): ByteArray {
        val input = ByteArrayInputStream(encrypted)
        val output = ByteArrayOutputStream()
        decryptTo(input, output, password)
        return output.toByteArray()
    }

    fun isEncrypted(prefix: ByteArray): Boolean {
        if (prefix.size < magic.size) return false
        for (i in magic.indices) {
            if (prefix[i] != magic[i]) return false
        }
        return true
    }

    private fun validateHeader(header: ByteArray) {
        if (header.size < 66) throw HlzEncryptionException("Truncated HLZENC header")
        for (i in magic.indices) {
            if (header[i] != magic[i]) throw HlzEncryptionException("Not an HLZENC v1 container")
        }
        if (header[8].toInt() and 0xff != KDF_ARGON2ID) throw HlzEncryptionException("Unsupported KDF")
        if (header[9].toInt() and 0xff != CIPHER_XCHACHA20_POLY1305_SECRETSTREAM) {
            throw HlzEncryptionException("Unsupported cipher")
        }
        val ops = readU32(header, 10)
        val memory = readU64(header, 14)
        val chunkSize = readU32(header, 22)
        if (ops != OPERATIONS_LIMIT.toLong() || memory != MEMORY_LIMIT_BYTES || chunkSize != CHUNK_SIZE_BYTES.toLong()) {
            throw HlzEncryptionException("Unsupported HLZENC parameters")
        }
    }

    private fun readFullyOrEof(input: InputStream, bytes: ByteArray): Boolean {
        var offset = 0
        while (offset < bytes.size) {
            val read = input.read(bytes, offset, bytes.size - offset)
            if (read == -1) return false
            offset += read
        }
        return true
    }

    private fun readUpTo(input: InputStream, bytes: ByteArray): Int {
        var offset = 0
        while (offset < bytes.size) {
            val read = input.read(bytes, offset, bytes.size - offset)
            if (read == -1) break
            offset += read
        }
        return offset
    }

    private fun buildHeader(salt: ByteArray, nonce: ByteArray): ByteArray {
        val header = ByteArray(66)
        magic.copyInto(header, 0)
        header[8] = KDF_ARGON2ID.toByte()
        header[9] = CIPHER_XCHACHA20_POLY1305_SECRETSTREAM.toByte()
        writeU32(header, 10, OPERATIONS_LIMIT)
        writeU64(header, 14, MEMORY_LIMIT_BYTES)
        writeU32(header, 22, CHUNK_SIZE_BYTES)
        salt.copyInto(header, 26)
        nonce.copyInto(header, 42)
        return header
    }

    private fun deriveKey(password: ByteArray, salt: ByteArray): ByteArray {
        val key = ByteArray(KEY_BYTES)
        val result = sodium.crypto_pwhash(
            key,
            key.size.toLong(),
            password,
            password.size.toLong(),
            salt,
            OPERATIONS_LIMIT.toLong(),
            NativeLong(MEMORY_LIMIT_BYTES),
            PwHash.Alg.PWHASH_ALG_ARGON2ID13.value,
        )
        if (result != 0) throw HlzEncryptionException("Argon2id key derivation failed")
        return key
    }

    private fun encryptFrame(key: ByteArray, nonce: ByteArray, aad: ByteArray, tag: Byte, plaintext: ByteArray): ByteArray {
        val ciphertext = ByteArray(plaintext.size + TAG_BYTES)
        val outputLength = LongArray(1) { ciphertext.size.toLong() }
        val result = sodium.crypto_aead_xchacha20poly1305_ietf_encrypt(
            ciphertext,
            outputLength,
            plaintext,
            plaintext.size.toLong(),
            aad,
            aad.size.toLong(),
            ByteArray(0),
            nonce,
            key,
        )
        if (result != 0) throw HlzEncryptionException("Frame encryption failed")
        val encryptedLength = outputLength[0].toInt()
        val frame = ByteArray(1 + encryptedLength)
        frame[0] = tag
        ciphertext.copyInto(frame, 1, 0, encryptedLength)
        return frame
    }

    private fun decryptFrame(key: ByteArray, nonce: ByteArray, aad: ByteArray, frame: ByteArray): Pair<Byte, ByteArray> {
        val tag = frame[0]
        val ciphertextLength = frame.size - 1
        if (ciphertextLength < TAG_BYTES) throw HlzEncryptionException("Frame too short")
        val ciphertext = frame.copyOfRange(1, frame.size)
        val plaintext = ByteArray(ciphertextLength - TAG_BYTES)
        val outputLength = LongArray(1) { plaintext.size.toLong() }
        val result = sodium.crypto_aead_xchacha20poly1305_ietf_decrypt(
            plaintext,
            outputLength,
            ByteArray(0),
            ciphertext,
            ciphertextLength.toLong(),
            aad,
            aad.size.toLong(),
            nonce,
            key,
        )
        if (result != 0) throw HlzEncryptionException("Frame authentication failed")
        val plaintextLength = outputLength[0].toInt()
        return tag to plaintext.copyOf(plaintextLength)
    }

    private fun normalizePassword(password: CharArray): ByteArray {
        return Normalizer.normalize(String(password), Normalizer.Form.NFC).toByteArray(Charsets.UTF_8)
    }

    private fun incrementNonce(nonce: ByteArray) {
        var carry = 1
        var index = nonce.size - 1
        while (carry != 0 && index >= 16) {
            val value = (nonce[index].toInt() and 0xff) + carry
            nonce[index] = value.toByte()
            carry = value shr 8
            index--
        }
    }

    private fun readU32(bytes: ByteArray, offset: Int): Long =
        ((bytes[offset].toLong() and 0xff) shl 24) or
            ((bytes[offset + 1].toLong() and 0xff) shl 16) or
            ((bytes[offset + 2].toLong() and 0xff) shl 8) or
            (bytes[offset + 3].toLong() and 0xff)

    private fun readU64(bytes: ByteArray, offset: Int): Long =
        ((bytes[offset].toLong() and 0xff) shl 56) or
            ((bytes[offset + 1].toLong() and 0xff) shl 48) or
            ((bytes[offset + 2].toLong() and 0xff) shl 40) or
            ((bytes[offset + 3].toLong() and 0xff) shl 32) or
            ((bytes[offset + 4].toLong() and 0xff) shl 24) or
            ((bytes[offset + 5].toLong() and 0xff) shl 16) or
            ((bytes[offset + 6].toLong() and 0xff) shl 8) or
            (bytes[offset + 7].toLong() and 0xff)

    private fun writeU32(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = (value ushr 24).toByte()
        bytes[offset + 1] = (value ushr 16).toByte()
        bytes[offset + 2] = (value ushr 8).toByte()
        bytes[offset + 3] = value.toByte()
    }

    private fun writeU64(bytes: ByteArray, offset: Int, value: Long) {
        bytes[offset] = (value ushr 56).toByte()
        bytes[offset + 1] = (value ushr 48).toByte()
        bytes[offset + 2] = (value ushr 40).toByte()
        bytes[offset + 3] = (value ushr 32).toByte()
        bytes[offset + 4] = (value ushr 24).toByte()
        bytes[offset + 5] = (value ushr 16).toByte()
        bytes[offset + 6] = (value ushr 8).toByte()
        bytes[offset + 7] = value.toByte()
    }

    private class HlzEncryptingOutputStream(
        private val target: OutputStream,
        password: CharArray,
    ) : FilterOutputStream(target) {
        private val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
        private val secretHeader = ByteArray(HEADER_BYTES).also(random::nextBytes)
        private val fixedHeader = buildHeader(salt, secretHeader)
        private val key = deriveKey(normalizePassword(password), salt)
        private val nonce = secretHeader.copyOf()
        private var pending: ByteArray? = null
        private val tail = ByteArrayOutputStream()

        init {
            target.write(fixedHeader)
        }

        override fun write(b: Int) {
            tail.write(b)
            drain()
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            tail.write(b, off, len)
            drain()
        }

        private fun drain() {
            while (tail.size() >= CHUNK_SIZE_BYTES) {
                val all = tail.toByteArray()
                val chunk = all.copyOfRange(0, CHUNK_SIZE_BYTES)
                val remainder = all.copyOfRange(CHUNK_SIZE_BYTES, all.size)
                if (pending != null) {
                    writeFrame(pending!!, TAG_MESSAGE)
                    incrementNonce(nonce)
                }
                pending = chunk
                tail.reset()
                tail.write(remainder)
            }
        }

        override fun close() {
            if (pending != null && tail.size() > 0) {
                writeFrame(pending!!, TAG_MESSAGE)
                incrementNonce(nonce)
                pending = null
            }
            val last = pending ?: tail.toByteArray()
            writeFrame(last, TAG_FINAL)
            target.flush()
            target.close()
        }

        private fun writeFrame(plaintext: ByteArray, tag: Byte) {
            val frame = encryptFrame(key, nonce, fixedHeader, tag, plaintext)
            target.write(frame.size ushr 24)
            target.write(frame.size ushr 16)
            target.write(frame.size ushr 8)
            target.write(frame.size)
            target.write(frame)
        }
    }
}

class HlzEncryptionException(message: String) : Exception(message)
