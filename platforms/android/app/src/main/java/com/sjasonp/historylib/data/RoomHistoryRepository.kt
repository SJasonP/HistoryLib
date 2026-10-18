package com.sjasonp.historylib.data

import com.sjasonp.historylib.core.dedup.DedupSignature
import com.sjasonp.historylib.core.dedup.RecordMerger
import com.sjasonp.historylib.core.model.DayCount
import com.sjasonp.historylib.core.model.HistoryQuery
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.HistorySortOrder
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.core.model.TopSite
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.repository.MergeResult
import com.sjasonp.historylib.core.repository.RecordTimeRange
import com.sjasonp.historylib.core.settings.AppSettingsRepository
import com.sjasonp.historylib.core.summary.SummaryCalculator
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import androidx.paging.PagingSource
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

class RoomHistoryRepository(
    private val dao: HistoryDao,
    private val settingsRepository: AppSettingsRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : HistoryRepository {
    private val mutationMutex = Mutex()
    override fun observeHistory(query: HistoryQuery): Flow<List<HistoryRecord>> {
        val pattern = "%${query.searchText.trim().lowercase(Locale.ROOT)}%"
        val start = query.startUsecInclusive
        val end = query.endUsecExclusive
        val flow = when {
            query.searchText.isNotBlank() -> dao.observeSearch(pattern)
            start != null && end != null -> dao.observeRange(start, end)
            else -> dao.observeAll()
        }

        return flow
            .map { entities ->
                val models = entities.map { it.toModel() }
                val filtered = if (query.sourceBrowsers.isEmpty()) {
                    models
                } else {
                    models.filter { it.sourceBrowser.lowercase() in query.sourceBrowsers.map(String::lowercase) }
                }
                if (query.sortOrder == HistorySortOrder.OLDEST_FIRST) filtered.reversed() else filtered
            }
            .flowOn(ioDispatcher)
    }

    override suspend fun loadHistoryPage(query: HistoryQuery, offset: Int, limit: Int): List<HistoryRecord> {
        require(offset >= 0)
        require(limit in 1..2_000)
        val start = query.startUsecInclusive
        val end = query.endUsecExclusive
        val rows = when {
            query.searchText.isNotBlank() -> dao.loadSearchPage(
                "%${query.searchText.trim().lowercase(Locale.ROOT)}%",
                offset,
                limit,
            )
            start != null && end != null -> dao.loadRangePage(start, end, offset, limit)
            else -> dao.loadPage(offset, limit)
        }
        return rows.map { it.toModel() }.let { records ->
            if (query.sourceBrowsers.isEmpty()) records
            else records.filter { it.sourceBrowser.lowercase() in query.sourceBrowsers.map(String::lowercase) }
        }.let { records ->
            if (query.sortOrder == HistorySortOrder.OLDEST_FIRST) records.reversed() else records
        }
    }

    override fun observeSummary(): Flow<SummarySnapshot> {
        return dao.observeSummary()
            .map { entity ->
                if (entity == null) SummaryCalculator.empty(0L)
                else entity.toModel(parseTopSites(entity.topSitesJson))
            }
            .flowOn(ioDispatcher)
    }

    override fun observeDirectoryCounts(): Flow<List<DayCount>> {
        return dao.observeDirectoryCounts()
            .map { rows ->
                rows.map { DayCount(it.year, it.month, it.day, it.recordCount) }
            }
            .flowOn(ioDispatcher)
    }

    override fun observeImportRuns(): Flow<List<ImportRun>> {
        return dao.observeImportRuns()
            .map { rows -> rows.map { it.toModel() } }
            .flowOn(ioDispatcher)
    }

    override suspend fun count(query: HistoryQuery): Long {
        val start = query.startUsecInclusive
        val end = query.endUsecExclusive
        return if (start != null && end != null) {
            dao.countRange(start, end)
        } else {
            dao.countAll()
        }
    }

    override suspend fun forEachRecord(
        query: HistoryQuery,
        pageSize: Int,
        block: suspend (List<HistoryRecord>) -> Unit,
    ) {
        val start = query.startUsecInclusive
        val end = query.endUsecExclusive
        val source = when {
            query.searchText.isNotBlank() ->
                dao.searchRecordsPagingSource("%${query.searchText.trim().lowercase(Locale.ROOT)}%")
            start != null && end != null -> dao.rangeRecordsPagingSource(start, end)
            else -> dao.allRecordsPagingSource()
        }
        var params: PagingSource.LoadParams<Int> = PagingSource.LoadParams.Refresh(0, pageSize, false)
        while (true) {
            val result = source.load(params) as? PagingSource.LoadResult.Page<Int, HistoryRecordEntity> ?: break
            val models = result.data.map { it.toModel() }.let { records ->
                if (query.sourceBrowsers.isEmpty()) records
                else records.filter { it.sourceBrowser.lowercase() in query.sourceBrowsers.map(String::lowercase) }
            }
            if (models.isNotEmpty()) block(models)
            val nextKey = result.nextKey ?: break
            params = PagingSource.LoadParams.Append(nextKey, pageSize, false)
        }
    }

    override suspend fun merge(
        records: List<HistoryRecord>,
        onProgress: suspend (processed: Int, merged: Int) -> Unit,
    ): MergeResult = mutationMutex.withLock {
        if (records.isEmpty()) return@withLock MergeResult(0, 0)
        val tolerance = settingsRepository.settings.first().nearDuplicateToleranceSeconds
        val entities = records.map { HistoryRecordEntity.from(it) }
        val candidateKeys = entities.flatMap { entity ->
            DedupSignature.from(entity.url, entity.visitedAtUsec, entity.sourceBrowser)
                .matchingKeys(tolerance)
        }.toSet()
        val existing = candidateKeys.chunked(SQLITE_BIND_CHUNK_SIZE)
            .flatMap { dao.findByUniqueKeys(it) }
            .associateBy { it.uniqueKey }
        val working = mutableMapOf<String, HistoryRecordEntity>()
        var inserted = 0
        var merged = 0

        entities.forEach { incoming ->
            val signature = DedupSignature.from(incoming.url, incoming.visitedAtUsec, incoming.sourceBrowser)
            val matchKey = signature.matchingKeys(tolerance).firstOrNull {
                working.containsKey(it) || existing.containsKey(it)
            }
            if (matchKey != null) {
                val base = working[matchKey] ?: existing[matchKey]!!
                val mergedModel = RecordMerger.merged(base.toModel(), incoming.toModel())
                working[matchKey] = HistoryRecordEntity.from(mergedModel, id = base.id)
                merged++
            } else {
                working[signature.canonicalKey()] = incoming
                inserted++
            }
        }

        dao.updateAll(working.values.filter { it.id != 0L })
        dao.insertAll(working.values.filter { it.id == 0L })
        onProgress(inserted, merged)
        MergeResult(inserted, merged)
    }

    override suspend fun delete(uniqueKeys: Set<String>): Int = mutationMutex.withLock {
        val count = dao.deleteByUniqueKeys(uniqueKeys)
        if (count > 0) refreshDerivedData()
        count
    }

    override suspend fun deleteRange(startUsecInclusive: Long, endUsecExclusive: Long): Int = mutationMutex.withLock {
        val count = dao.deleteRange(startUsecInclusive, endUsecExclusive)
        if (count > 0) refreshDerivedData()
        count
    }

    override suspend fun deleteAll(): Int = mutationMutex.withLock {
        val count = dao.deleteAll()
        if (count > 0) refreshDerivedData()
        count
    }

    override suspend fun recordTimeRangeUsec(): RecordTimeRange? {
        val range = dao.recordTimeRange()
        val earliest = range.minUsec ?: return null
        val latest = range.maxUsec ?: return null
        return RecordTimeRange(earliestUsec = earliest, latestUsec = latest)
    }

    override suspend fun regenerateSummary(nowUsec: Long) {
        val total = dao.totalRecords()
        val snapshot = if (total == 0L) {
            SummaryCalculator.empty(nowUsec)
        } else {
            val range = dao.timeRange()
            val topSites = dao.topSites().map { TopSite(it.host, it.cnt) }
            SummaryCalculator.compute(
                totalRecords = total,
                earliestVisitUsec = range.minUsec ?: 0L,
                latestVisitUsec = range.maxUsec ?: 0L,
                topSites = topSites,
                generatedAtUsec = nowUsec,
            )
        }
        dao.upsertSummary(
            SummarySnapshotEntity(
                totalRecords = snapshot.totalRecords,
                averagePerDay = snapshot.averagePerDay,
                averagePerMonth = snapshot.averagePerMonth,
                averagePerYear = snapshot.averagePerYear,
                earliestVisitUsec = snapshot.earliestVisitUsec,
                latestVisitUsec = snapshot.latestVisitUsec,
                generatedAtUsec = snapshot.generatedAtUsec,
                topSitesJson = topSitesJson(snapshot.topSites),
            ),
        )
    }

    override suspend fun regenerateDirectoryCounts(zoneId: String) {
        val rows = dao.directoryCountRows()
        dao.clearDirectoryCounts()
        val entities = rows.mapNotNull { row ->
            val year = row.year.toIntOrNull() ?: return@mapNotNull null
            val month = row.month.toIntOrNull() ?: return@mapNotNull null
            val day = row.day.toIntOrNull() ?: return@mapNotNull null
            DirectoryCountEntity(year = year, month = month, day = day, recordCount = row.recordCount)
        }
        dao.insertDirectoryCounts(entities)
    }

    override suspend fun recordImportRun(run: ImportRun): Long =
        dao.insertImportRun(ImportRunEntity.from(run))

    override suspend fun cancelInterruptedImportRuns(finishedAtUsec: Long): Int =
        dao.cancelInterruptedImportRuns(finishedAtUsec)

    override suspend fun refreshDerivedData() {
        val now = System.currentTimeMillis() * 1000L
        regenerateSummary(now)
        regenerateDirectoryCounts(java.time.ZoneId.systemDefault().id)
    }

    private fun topSitesJson(sites: List<TopSite>): String {
        val array = JSONArray()
        sites.forEach { site ->
            array.put(JSONObject().put("host", site.host).put("count", site.count))
        }
        return array.toString()
    }

    private fun parseTopSites(json: String): List<TopSite> {
        if (json.isBlank()) return emptyList()
        return buildList {
            val array = JSONArray(json)
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                add(TopSite(host = obj.getString("host"), count = obj.getLong("count")))
            }
        }
    }

    companion object {
        private const val SQLITE_BIND_CHUNK_SIZE = 900
    }
}
