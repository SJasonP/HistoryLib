package com.sjasonp.historylib.core.model

data class HistoryQuery(
    val searchText: String = "",
    val startUsecInclusive: Long? = null,
    val endUsecExclusive: Long? = null,
    val sourceBrowsers: Set<String> = emptySet(),
    val sortOrder: HistorySortOrder = HistorySortOrder.NEWEST_FIRST,
)

enum class HistorySortOrder {
    NEWEST_FIRST,
    OLDEST_FIRST,
}
