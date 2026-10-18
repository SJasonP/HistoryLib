package com.sjasonp.historylib.data

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.sjasonp.historylib.core.dedup.UrlNormalizer
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.ImportRunStatus
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.core.model.TopSite
import java.util.Locale

@Entity(
    tableName = "history_records",
    indices = [
        Index("uniqueKey"),
        Index("visitedAtUsec"),
        Index("host"),
    ],
)
data class HistoryRecordEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val uniqueKey: String,
    val url: String,
    val title: String,
    val visitedAtUsec: Long,
    val visitCount: Int,
    val sourceBrowser: String,
    val sourceFileName: String,
    val rawTimeUsec: Long,
    val sourceUrl: String?,
    val sourceTimeUsec: Long?,
    val destinationUrl: String?,
    val destinationTimeUsec: Long?,
    val latestVisitWasHttpGet: Boolean?,
    val importedAtUsec: Long,
    val host: String,
    val urlFold: String,
    val titleFold: String,
) {
    fun toModel(): HistoryRecord = HistoryRecord(
        uniqueKey = uniqueKey,
        url = url,
        title = title,
        visitedAtUsec = visitedAtUsec,
        visitCount = visitCount,
        sourceBrowser = sourceBrowser,
        sourceFileName = sourceFileName,
        rawTimeUsec = rawTimeUsec,
        sourceUrl = sourceUrl,
        sourceTimeUsec = sourceTimeUsec,
        destinationUrl = destinationUrl,
        destinationTimeUsec = destinationTimeUsec,
        latestVisitWasHttpGet = latestVisitWasHttpGet,
        importedAtUsec = importedAtUsec,
    )

    companion object {
        fun from(model: HistoryRecord, id: Long = 0): HistoryRecordEntity = HistoryRecordEntity(
            id = id,
            uniqueKey = model.uniqueKey,
            url = model.url,
            title = model.title,
            visitedAtUsec = model.visitedAtUsec,
            visitCount = model.visitCount,
            sourceBrowser = model.sourceBrowser,
            sourceFileName = model.sourceFileName,
            rawTimeUsec = model.rawTimeUsec,
            sourceUrl = model.sourceUrl,
            sourceTimeUsec = model.sourceTimeUsec,
            destinationUrl = model.destinationUrl,
            destinationTimeUsec = model.destinationTimeUsec,
            latestVisitWasHttpGet = model.latestVisitWasHttpGet,
            importedAtUsec = model.importedAtUsec,
            host = UrlNormalizer.hostOrDefault(model.url),
            urlFold = model.url.lowercase(Locale.ROOT),
            titleFold = model.title.lowercase(Locale.ROOT),
        )
    }
}

@Entity(tableName = "directory_counts")
data class DirectoryCountEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val year: Int,
    val month: Int,
    val day: Int,
    val recordCount: Long,
)

@Entity(tableName = "summary_snapshot")
data class SummarySnapshotEntity(
    @PrimaryKey val id: Int = 1,
    val totalRecords: Long,
    val averagePerDay: Double,
    val averagePerMonth: Double,
    val averagePerYear: Double,
    val earliestVisitUsec: Long?,
    val latestVisitUsec: Long?,
    val generatedAtUsec: Long,
    val topSitesJson: String,
) {
    fun toModel(topSites: List<TopSite>): SummarySnapshot = SummarySnapshot(
        totalRecords = totalRecords,
        averagePerDay = averagePerDay,
        averagePerMonth = averagePerMonth,
        averagePerYear = averagePerYear,
        earliestVisitUsec = earliestVisitUsec,
        latestVisitUsec = latestVisitUsec,
        generatedAtUsec = generatedAtUsec,
        topSites = topSites,
    )
}

@Entity(tableName = "import_runs")
data class ImportRunEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val startedAtUsec: Long,
    val finishedAtUsec: Long?,
    val resolvedFormat: String,
    val status: String,
    val scannedFileCount: Int,
    val validFileCount: Int,
    val importedRecordCount: Int,
    val skippedRecordCount: Int,
    val failureMessage: String?,
) {
    fun toModel(): ImportRun = ImportRun(
        id = id,
        startedAtUsec = startedAtUsec,
        finishedAtUsec = finishedAtUsec,
        resolvedFormat = resolvedFormat,
        status = ImportRunStatus.valueOf(status),
        scannedFileCount = scannedFileCount,
        validFileCount = validFileCount,
        importedRecordCount = importedRecordCount,
        skippedRecordCount = skippedRecordCount,
        failureMessage = failureMessage,
    )

    companion object {
        fun from(model: ImportRun): ImportRunEntity = ImportRunEntity(
            id = model.id,
            startedAtUsec = model.startedAtUsec,
            finishedAtUsec = model.finishedAtUsec,
            resolvedFormat = model.resolvedFormat,
            status = model.status.name,
            scannedFileCount = model.scannedFileCount,
            validFileCount = model.validFileCount,
            importedRecordCount = model.importedRecordCount,
            skippedRecordCount = model.skippedRecordCount,
            failureMessage = model.failureMessage,
        )
    }
}
