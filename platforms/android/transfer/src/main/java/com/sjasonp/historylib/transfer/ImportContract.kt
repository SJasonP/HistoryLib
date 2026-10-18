package com.sjasonp.historylib.transfer

data class ImportRequest(
    val source: TransferSource,
    val archivePassword: SecretProvider? = null,
)

fun interface SecretProvider {
    suspend fun requestSecret(): CharArray?
}

enum class HistoryImportFormat {
    SAFARI,
    CHROME_TAKEOUT,
    HISTORYLIB_ARCHIVE,
}

data class ImportReport(
    val resolvedFormat: HistoryImportFormat?,
    val scannedFileCount: Int,
    val validFileCount: Int,
    val importedRecordCount: Int,
    val skippedRecordCount: Int,
    val failures: List<ImportFailure> = emptyList(),
    val cancelled: Boolean = false,
) {
    init {
        require(scannedFileCount >= 0)
        require(validFileCount in 0..scannedFileCount)
        require(importedRecordCount >= 0)
        require(skippedRecordCount >= 0)
    }
}

data class ImportFailure(
    val displayName: String,
    val category: ImportFailureCategory,
    val userMessage: String,
)

enum class ImportFailureCategory {
    UNRECOGNIZED_INPUT,
    INVALID_STRUCTURE,
    CHECKSUM_MISMATCH,
    AUTHENTICATION_FAILED,
    IO_ERROR,
    CANCELLED,
}

interface HistoryImporter {
    suspend fun importHistory(
        request: ImportRequest,
        onProgress: suspend (TransferProgress) -> Unit = {},
    ): ImportReport
}
