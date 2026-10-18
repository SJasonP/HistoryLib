package com.sjasonp.historylib.transfer

import com.sjasonp.historylib.core.model.HistoryQuery

data class ExportRequest(
    val format: HistoryExportFormat,
    val destination: TransferDestination,
    val query: HistoryQuery = HistoryQuery(),
    val split: HistoryExportSplit = HistoryExportSplit.SINGLE,
    val archivePassword: SecretProvider? = null,
)

enum class HistoryExportFormat {
    SAFARI_JSON,
    HISTORYLIB_ARCHIVE,
}

enum class HistoryExportSplit {
    SINGLE,
    BY_DAY,
    BY_MONTH,
    BY_YEAR,
}

data class ExportReport(
    val exportedRecordCount: Int,
    val createdFileNames: List<String>,
    val cancelled: Boolean = false,
) {
    init {
        require(exportedRecordCount >= 0)
    }
}

interface HistoryExporter {
    suspend fun export(
        request: ExportRequest,
        onProgress: suspend (TransferProgress) -> Unit = {},
    ): ExportReport
}
