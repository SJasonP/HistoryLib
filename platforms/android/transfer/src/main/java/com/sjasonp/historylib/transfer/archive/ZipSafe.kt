package com.sjasonp.historylib.transfer.archive

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream

object ZipSafe {
    const val MAX_ENTRY_COUNT = 100_000
    const val MAX_METADATA_BYTES = 16L * 1024L * 1024L
    const val MAX_TOTAL_METADATA_BYTES = 64L * 1024L * 1024L
    const val MAX_RECORD_BYTES = 4 * 1024 * 1024
    private val zipMagics = listOf(
        byteArrayOf(0x50, 0x4B, 0x03, 0x04),
        byteArrayOf(0x50, 0x4B, 0x05, 0x06),
        byteArrayOf(0x50, 0x4B, 0x07, 0x08),
    )

    fun isZip(prefix: ByteArray): Boolean {
        if (prefix.size < 4) return false
        return zipMagics.any { magic ->
            prefix.take(magic.size).withIndex().all { (i, b) -> b == magic[i] }
        }
    }

    fun safeEntryName(name: String): String {
        if (name.isEmpty()) throw ZipValidationException("Empty ZIP entry name")
        if (name.startsWith("/") || name.contains("\\")) throw ZipValidationException("Absolute or non-portable ZIP path")
        val parts = name.split("/")
        if (parts.any { it == ".." }) throw ZipValidationException("ZIP path traversal")
        return name
    }

    fun readFully(input: InputStream, limitBytes: Long = MAX_METADATA_BYTES): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read == -1) break
            total += read
            if (total > limitBytes) throw ZipValidationException("ZIP entry exceeds size limit")
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    fun forEachEntry(input: InputStream, block: (ZipInputStream, ZipEntry) -> Unit) {
        ZipInputStream(input).use { zip ->
            val seen = mutableSetOf<String>()
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = safeEntryName(entry.name)
                if (!seen.add(name)) throw ZipValidationException("Duplicate ZIP entry: $name")
                block(zip, ZipEntry(name))
            }
            zip.closeEntry()
        }
    }
}

class ZipValidationException(message: String) : Exception(message)
