package com.sjasonp.historylib.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import androidx.paging.PagingSource
import kotlinx.coroutines.flow.Flow

@Dao
interface HistoryDao {
    @Query("SELECT * FROM history_records ORDER BY visitedAtUsec DESC")
    fun observeAll(): Flow<List<HistoryRecordEntity>>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE urlFold LIKE :pattern OR titleFold LIKE :pattern " +
            "ORDER BY visitedAtUsec DESC",
    )
    fun observeSearch(pattern: String): Flow<List<HistoryRecordEntity>>

    @Query("SELECT * FROM history_records ORDER BY visitedAtUsec DESC LIMIT :limit OFFSET :offset")
    suspend fun loadPage(offset: Int, limit: Int): List<HistoryRecordEntity>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE urlFold LIKE :pattern OR titleFold LIKE :pattern " +
            "ORDER BY visitedAtUsec DESC LIMIT :limit OFFSET :offset",
    )
    suspend fun loadSearchPage(pattern: String, offset: Int, limit: Int): List<HistoryRecordEntity>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE visitedAtUsec >= :start AND visitedAtUsec < :end " +
            "ORDER BY visitedAtUsec DESC LIMIT :limit OFFSET :offset",
    )
    suspend fun loadRangePage(start: Long, end: Long, offset: Int, limit: Int): List<HistoryRecordEntity>

    @Query("SELECT * FROM history_records ORDER BY visitedAtUsec ASC")
    fun allRecordsPagingSource(): PagingSource<Int, HistoryRecordEntity>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE urlFold LIKE :pattern OR titleFold LIKE :pattern " +
            "ORDER BY visitedAtUsec ASC",
    )
    fun searchRecordsPagingSource(pattern: String): PagingSource<Int, HistoryRecordEntity>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE visitedAtUsec >= :start AND visitedAtUsec < :end " +
            "ORDER BY visitedAtUsec ASC",
    )
    fun rangeRecordsPagingSource(start: Long, end: Long): PagingSource<Int, HistoryRecordEntity>

    @Query(
        "SELECT * FROM history_records " +
            "WHERE visitedAtUsec >= :start AND visitedAtUsec < :end " +
            "ORDER BY visitedAtUsec DESC",
    )
    fun observeRange(start: Long, end: Long): Flow<List<HistoryRecordEntity>>

    @Query("SELECT * FROM history_records WHERE uniqueKey IN (:keys)")
    suspend fun findByUniqueKeys(keys: List<String>): List<HistoryRecordEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(records: List<HistoryRecordEntity>)

    @Update
    suspend fun updateAll(records: List<HistoryRecordEntity>)

    @Query("DELETE FROM history_records WHERE uniqueKey IN (:keys)")
    suspend fun deleteByUniqueKeys(keys: Set<String>): Int

    @Query("DELETE FROM history_records WHERE visitedAtUsec >= :start AND visitedAtUsec < :end")
    suspend fun deleteRange(start: Long, end: Long): Int

    @Query("DELETE FROM history_records")
    suspend fun deleteAll(): Int

    @Query("SELECT COUNT(*) FROM history_records")
    suspend fun countAll(): Long

    @Query("SELECT COUNT(*) FROM history_records WHERE visitedAtUsec >= :start AND visitedAtUsec < :end")
    suspend fun countRange(start: Long, end: Long): Long

    @Query("SELECT COUNT(*) FROM history_records")
    suspend fun totalRecords(): Long

    @Query("SELECT MIN(visitedAtUsec) AS minUsec, MAX(visitedAtUsec) AS maxUsec FROM history_records")
    suspend fun timeRange(): TimeRangeRow

    @Query("SELECT MIN(visitedAtUsec) AS minUsec, MAX(visitedAtUsec) AS maxUsec FROM history_records")
    suspend fun recordTimeRange(): TimeRangeRow

    @Query(
        "SELECT host, COUNT(*) AS cnt FROM history_records " +
            "GROUP BY host ORDER BY cnt DESC, host ASC LIMIT 10",
    )
    suspend fun topSites(): List<TopSiteRow>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSummary(entity: SummarySnapshotEntity)

    @Query("SELECT * FROM summary_snapshot WHERE id = 1")
    fun observeSummary(): Flow<SummarySnapshotEntity?>

    @Query("SELECT * FROM directory_counts ORDER BY year DESC, month DESC, day DESC")
    fun observeDirectoryCounts(): Flow<List<DirectoryCountEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDirectoryCounts(rows: List<DirectoryCountEntity>)

    @Query("DELETE FROM directory_counts")
    suspend fun clearDirectoryCounts()

    @Query(
        "SELECT strftime('%Y', visitedAtUsec / 1000000, 'unixepoch', 'localtime') AS year, " +
            "strftime('%m', visitedAtUsec / 1000000, 'unixepoch', 'localtime') AS month, " +
            "strftime('%d', visitedAtUsec / 1000000, 'unixepoch', 'localtime') AS day, " +
            "COUNT(*) AS recordCount FROM history_records " +
            "GROUP BY year, month, day ORDER BY year DESC, month DESC, day DESC",
    )
    suspend fun directoryCountRows(): List<DirectoryCountSqlRow>

    @Query("SELECT * FROM import_runs ORDER BY startedAtUsec DESC LIMIT 50")
    fun observeImportRuns(): Flow<List<ImportRunEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertImportRun(entity: ImportRunEntity): Long

    @Query(
        "UPDATE import_runs SET status = 'CANCELLED', finishedAtUsec = :finishedAtUsec, " +
            "failureMessage = 'Interrupted by process termination' WHERE status = 'RUNNING'",
    )
    suspend fun cancelInterruptedImportRuns(finishedAtUsec: Long): Int
}

data class TimeRangeRow(
    val minUsec: Long?,
    val maxUsec: Long?,
)

data class TopSiteRow(
    val host: String,
    val cnt: Long,
)

data class DirectoryCountSqlRow(
    val year: String,
    val month: String,
    val day: String,
    val recordCount: Long,
)
