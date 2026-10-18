package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.transfer.archive.ZipValidationException
import org.junit.Assert.assertThrows
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class HistoryLibArchiveValidationTest {
    @Test
    fun rejectsMalformedRecordBeforeImport() {
        val archive = archiveWithChunk("{not-json}\n")
        val importer = HistoryLibArchiveImporter()
        val metadata = importer.readManifest(ByteArrayInputStream(archive))

        assertThrows(ZipValidationException::class.java) {
            importer.validate(ByteArrayInputStream(archive), metadata)
        }
    }

    @Test
    fun rejectsRecordMissingRequiredFieldsBeforeImport() {
        val archive = archiveWithChunk("{\"t\":\"missing url and time\"}\n")
        val importer = HistoryLibArchiveImporter()
        val metadata = importer.readManifest(ByteArrayInputStream(archive))

        assertThrows(ZipValidationException::class.java) {
            importer.validate(ByteArrayInputStream(archive), metadata)
        }
    }

    @Test
    fun rejectsUnindexedChunkDuringRecordImport() {
        val archive = archiveWithChunk(
            "{\"u\":\"https://example.com\",\"ts\":1}\n",
            extraChunk = "{\"u\":\"https://attacker.example\",\"ts\":2}\n",
        )
        val importer = HistoryLibArchiveImporter()
        val metadata = importer.readManifest(ByteArrayInputStream(archive))

        assertThrows(ZipValidationException::class.java) {
            importer.validate(ByteArrayInputStream(archive), metadata)
        }
    }

    private fun archiveWithChunk(chunkText: String, extraChunk: String? = null): ByteArray {
        val chunk = chunkText.toByteArray()
        val hash = MessageDigest.getInstance("SHA-256").digest(chunk)
            .joinToString("") { "%02x".format(it) }
        val manifest = """
            {"format":"historylib","format_version":1,"created_at_usec":1,
             "app_version":"1.4","record_count":1,"chunk_count":1,
             "indexes":{"chunks":"indexes/chunks.json"}}
        """.trimIndent().toByteArray()
        val chunks = """
            [{"id":1,"path":"chunks/00000001.jsonl","record_count":1,
              "min_ts":1,"max_ts":1,"sha256":"$hash"}]
        """.trimIndent().toByteArray()

        return ByteArrayOutputStream().also { output ->
            ZipOutputStream(output).use { zip ->
                zip.writeEntry("manifest.json", manifest)
                zip.writeEntry("indexes/chunks.json", chunks)
                zip.writeEntry("chunks/00000001.jsonl", chunk)
                extraChunk?.let { zip.writeEntry("chunks/extra.jsonl", it.toByteArray()) }
            }
        }.toByteArray()
    }

    private fun ZipOutputStream.writeEntry(name: String, bytes: ByteArray) {
        putNextEntry(ZipEntry(name))
        write(bytes)
        closeEntry()
    }
}
