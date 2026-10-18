package com.sjasonp.historylib.transfer

import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.transfer.export.HistoryLibArchiveExporter
import com.sjasonp.historylib.transfer.export.SafariExporter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DefaultHistoryExporter(
    private val repository: HistoryRepository,
    private val appVersion: String,
    private val clockUsec: () -> Long = { System.currentTimeMillis() * 1000L },
) : HistoryExporter {
    private val safariExporter = SafariExporter()
    private val archiveExporter = HistoryLibArchiveExporter()

    override suspend fun export(
        request: ExportRequest,
        onProgress: suspend (TransferProgress) -> Unit,
    ): ExportReport = withContext(Dispatchers.IO) {
        onProgress(TransferProgress(TransferPhase.READING))
        val now = clockUsec()
        val fileName = when (request.format) {
            HistoryExportFormat.SAFARI_JSON -> "History-Safari.zip"
            HistoryExportFormat.HISTORYLIB_ARCHIVE -> "History.hlz"
        }
        val forEachBatch: suspend (suspend (List<com.sjasonp.historylib.core.model.HistoryRecord>) -> Unit) -> Unit = { block ->
            repository.forEachRecord(request.query, EXPORT_PAGE_SIZE, block)
        }

        onProgress(TransferProgress(TransferPhase.WRITING))
        val exportedCount = request.destination.withOutputStream(fileName) { output ->
            when (request.format) {
                HistoryExportFormat.SAFARI_JSON ->
                    safariExporter.exportTo(forEachBatch, request.split, now, output)
                HistoryExportFormat.HISTORYLIB_ARCHIVE -> {
                    val password = request.archivePassword?.requestSecret()
                    archiveExporter.exportTo(forEachBatch, output, appVersion, now, password)
                }
            }
        }

        onProgress(TransferProgress(TransferPhase.CLEANING_UP))
        ExportReport(
            exportedRecordCount = exportedCount.toInt(),
            createdFileNames = listOf(fileName),
        )
    }

    companion object {
        private const val EXPORT_PAGE_SIZE = 5_000
    }
}
