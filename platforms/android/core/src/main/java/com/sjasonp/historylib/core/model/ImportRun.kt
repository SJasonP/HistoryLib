package com.sjasonp.historylib.core.model

data class ImportRun(
    val id: Long = 0,
    val startedAtUsec: Long,
    val finishedAtUsec: Long? = null,
    val resolvedFormat: String,
    val status: ImportRunStatus,
    val scannedFileCount: Int = 0,
    val validFileCount: Int = 0,
    val importedRecordCount: Int = 0,
    val skippedRecordCount: Int = 0,
    val failureMessage: String? = null,
)

enum class ImportRunStatus {
    RUNNING,
    COMPLETED,
    FAILED,
    CANCELLED,
}
