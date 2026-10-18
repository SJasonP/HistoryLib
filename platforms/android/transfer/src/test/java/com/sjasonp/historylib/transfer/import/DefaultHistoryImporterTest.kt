package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.core.model.DayCount
import com.sjasonp.historylib.core.model.HistoryQuery
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.repository.MergeResult
import com.sjasonp.historylib.core.repository.RecordTimeRange
import com.sjasonp.historylib.core.summary.SummaryCalculator
import com.sjasonp.historylib.transfer.DefaultHistoryImporter
import com.sjasonp.historylib.transfer.ImportRequest
import com.sjasonp.historylib.transfer.ScratchFile
import com.sjasonp.historylib.transfer.TransferScratch
import com.sjasonp.historylib.transfer.TransferSource
import com.sjasonp.historylib.transfer.TransferSourceKind
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultHistoryImporterTest {
    @Test
    fun importsSharedSafariFixtureAndRefreshesDerivedDataOnce() = runBlocking {
        val repository = RecordingRepository()
        val report = DefaultHistoryImporter(repository, UnusedScratch).importHistory(
            ImportRequest(ByteArraySource("safari-valid.json", fixture("import/safari-valid.json"))),
        )

        assertEquals(2, report.importedRecordCount)
        assertEquals(2, repository.records.size)
        assertEquals(1, repository.refreshCount)
    }

    @Test
    fun unknownSharedFixtureLeavesRepositoryUnchanged() = runBlocking {
        val repository = RecordingRepository()
        val report = DefaultHistoryImporter(repository, UnusedScratch).importHistory(
            ImportRequest(ByteArraySource("unknown.json", fixture("import/unknown-browser-history-string.json"))),
        )

        assertEquals(0, repository.records.size)
        assertEquals(0, repository.refreshCount)
        assertTrue(report.failures.isNotEmpty())
    }

    private fun fixture(path: String): ByteArray {
        return File(requireNotNull(System.getProperty("historylib.sharedFixtures")), path).readBytes()
    }
}

private class ByteArraySource(
    override val displayName: String,
    private val bytes: ByteArray,
) : TransferSource {
    override val kind: TransferSourceKind = TransferSourceKind.FILE
    override suspend fun <T> withInputStream(block: suspend (InputStream) -> T): T =
        ByteArrayInputStream(bytes).use { block(it) }
}

private object UnusedScratch : TransferScratch {
    override suspend fun <T> withTempFile(suffix: String, block: suspend (ScratchFile) -> T): T =
        error("Scratch storage was not expected")
}

private class RecordingRepository : HistoryRepository {
    val records = mutableListOf<HistoryRecord>()
    var refreshCount = 0

    override fun observeHistory(query: HistoryQuery): Flow<List<HistoryRecord>> = MutableStateFlow(records)
    override suspend fun loadHistoryPage(query: HistoryQuery, offset: Int, limit: Int) = records.drop(offset).take(limit)
    override fun observeSummary(): Flow<SummarySnapshot> = MutableStateFlow(SummaryCalculator.empty(0))
    override fun observeDirectoryCounts(): Flow<List<DayCount>> = MutableStateFlow(emptyList())
    override fun observeImportRuns(): Flow<List<ImportRun>> = MutableStateFlow(emptyList())
    override suspend fun count(query: HistoryQuery): Long = records.size.toLong()
    override suspend fun forEachRecord(query: HistoryQuery, pageSize: Int, block: suspend (List<HistoryRecord>) -> Unit) {
        records.chunked(pageSize).forEach { block(it) }
    }
    override suspend fun merge(records: List<HistoryRecord>, onProgress: suspend (Int, Int) -> Unit): MergeResult {
        this.records += records
        onProgress(records.size, 0)
        return MergeResult(records.size, 0)
    }
    override suspend fun delete(uniqueKeys: Set<String>): Int = 0
    override suspend fun deleteRange(startUsecInclusive: Long, endUsecExclusive: Long): Int = 0
    override suspend fun deleteAll(): Int = 0
    override suspend fun recordTimeRangeUsec(): RecordTimeRange? = null
    override suspend fun regenerateSummary(nowUsec: Long) = Unit
    override suspend fun regenerateDirectoryCounts(zoneId: String) = Unit
    override suspend fun refreshDerivedData() { refreshCount++ }
    override suspend fun recordImportRun(run: ImportRun): Long = run.id
    override suspend fun cancelInterruptedImportRuns(finishedAtUsec: Long): Int = 0
}
