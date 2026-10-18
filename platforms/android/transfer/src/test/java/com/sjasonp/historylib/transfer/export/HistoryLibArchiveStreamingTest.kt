package com.sjasonp.historylib.transfer.export

import com.goterl.lazysodium.SodiumJava
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.archive.HlzEncryption
import com.sjasonp.historylib.transfer.import.HistoryLibArchiveImporter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import kotlinx.coroutines.runBlocking
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

class HistoryLibArchiveStreamingTest {
    @Before
    fun useDesktopLibsodium() {
        HlzEncryption.setSodiumForTesting(SodiumJava())
    }

    @Test
    fun streamsExportAndReimportsRoundTrip() {
        val records = (1..1_200).map { index ->
            HistoryRecord(
                uniqueKey = "https://example.com/$index|1_700_000_000|chrome",
                url = "https://example.com/$index",
                title = "Page $index",
                visitedAtUsec = 1_700_000_000_000_000L + index,
                visitCount = 1,
                sourceBrowser = "Chrome",
                sourceFileName = "History.json",
                rawTimeUsec = 1_700_000_000_000_000L + index,
                importedAtUsec = 2L,
            )
        }
        val output = ByteArrayOutputStream()
        val exporter = HistoryLibArchiveExporter()
        val count = runBlocking {
            exporter.exportTo(
                forEachBatch = { block -> for (chunk in records.chunked(300)) block(chunk) },
                out = output,
                appVersion = "1.4",
                exportTimeUsec = 3L,
                password = null,
            )
        }
        assertEquals(records.size.toLong(), count)

        val importer = HistoryLibArchiveImporter()
        val metadata = importer.readManifest(ByteArrayInputStream(output.toByteArray()))
        importer.validate(ByteArrayInputStream(output.toByteArray()), metadata)
        val imported = importer.records(ByteArrayInputStream(output.toByteArray()), metadata, 3L).filterNotNull().toList()
        assertEquals(records.size, imported.size)
    }

    @Test
    fun streamsEncryptedExportAndDecryptsBack() {
        val plaintext = ByteArray(2_400_000) { it.toByte() }
        val ciphertext = ByteArrayOutputStream()
        val exporter = HistoryLibArchiveExporter()
        runBlocking {
            exporter.exportTo(
                forEachBatch = { block -> block(emptyList()) },
                out = ciphertext,
                appVersion = "1.4",
                exportTimeUsec = 3L,
                password = "correct horse battery staple".toCharArray(),
            )
        }
        assertTrue(ciphertext.size() > 0)
        val decrypted = ByteArrayOutputStream()
        HlzEncryption.decryptTo(ByteArrayInputStream(ciphertext.toByteArray()), decrypted, "correct horse battery staple".toCharArray())
        assertTrue(decrypted.size() > 0)
    }
}
