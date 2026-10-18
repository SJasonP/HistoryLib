package com.sjasonp.historylib.core.repository

import com.sjasonp.historylib.core.model.HistoryQuery
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.DayCount
import com.sjasonp.historylib.core.model.SummarySnapshot
import kotlinx.coroutines.flow.Flow

interface HistoryRepository {
    fun observeHistory(query: HistoryQuery): Flow<List<HistoryRecord>>

    suspend fun loadHistoryPage(query: HistoryQuery, offset: Int, limit: Int): List<HistoryRecord>

    fun observeSummary(): Flow<SummarySnapshot>

    fun observeDirectoryCounts(): Flow<List<DayCount>>

    fun observeImportRuns(): Flow<List<ImportRun>>

    suspend fun count(query: HistoryQuery): Long

    suspend fun forEachRecord(
        query: HistoryQuery,
        pageSize: Int = 5_000,
        block: suspend (List<HistoryRecord>) -> Unit,
    )

    suspend fun merge(
        records: List<HistoryRecord>,
        onProgress: suspend (processed: Int, merged: Int) -> Unit = { _, _ -> },
    ): MergeResult

    suspend fun delete(uniqueKeys: Set<String>): Int

    suspend fun deleteRange(startUsecInclusive: Long, endUsecExclusive: Long): Int

    suspend fun deleteAll(): Int

    suspend fun recordTimeRangeUsec(): RecordTimeRange?

    suspend fun regenerateSummary(nowUsec: Long): Unit

    suspend fun regenerateDirectoryCounts(zoneId: String): Unit

    suspend fun refreshDerivedData(): Unit

    suspend fun recordImportRun(run: ImportRun): Long

    suspend fun cancelInterruptedImportRuns(finishedAtUsec: Long): Int
}

data class RecordTimeRange(
    val earliestUsec: Long,
    val latestUsec: Long,
)

data class MergeResult(
    val insertedCount: Int,
    val mergedCount: Int,
)
