package com.sjasonp.historylib.core.model

/**
 * Platform-neutral history record. All timestamps are Unix microseconds in UTC.
 * See shared/specs/history-record.md before changing this schema.
 */
data class HistoryRecord(
    val uniqueKey: String,
    val url: String,
    val title: String,
    val visitedAtUsec: Long,
    val visitCount: Int,
    val sourceBrowser: String,
    val sourceFileName: String,
    val rawTimeUsec: Long,
    val sourceUrl: String? = null,
    val sourceTimeUsec: Long? = null,
    val destinationUrl: String? = null,
    val destinationTimeUsec: Long? = null,
    val latestVisitWasHttpGet: Boolean? = null,
    val importedAtUsec: Long,
) {
    init {
        require(uniqueKey.isNotBlank()) { "uniqueKey must not be blank" }
        require(url.isNotBlank()) { "url must not be blank" }
        require(visitCount >= 1) { "visitCount must be at least 1" }
    }
}
