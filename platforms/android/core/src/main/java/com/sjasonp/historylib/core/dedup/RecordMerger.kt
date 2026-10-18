package com.sjasonp.historylib.core.dedup

import com.sjasonp.historylib.core.model.HistoryRecord

object RecordMerger {
    fun merged(existing: HistoryRecord, incoming: HistoryRecord): HistoryRecord {
        return existing.copy(
            visitCount = existing.visitCount + incoming.visitCount.coerceAtLeast(1),
            title = richerText(existing.title, incoming.title),
            sourceUrl = richer(existing.sourceUrl, incoming.sourceUrl),
            sourceTimeUsec = richer(existing.sourceTimeUsec, incoming.sourceTimeUsec),
            destinationUrl = richer(existing.destinationUrl, incoming.destinationUrl),
            destinationTimeUsec = richer(existing.destinationTimeUsec, incoming.destinationTimeUsec),
            latestVisitWasHttpGet = existing.latestVisitWasHttpGet ?: incoming.latestVisitWasHttpGet,
        )
    }

    private fun richer(existing: String?, incoming: String?): String? {
        return when {
            existing.isNullOrBlank() -> incoming
            incoming.isNullOrBlank() -> existing
            else -> existing
        }
    }

    private fun richerText(existing: String, incoming: String): String {
        return if (existing.isBlank() && incoming.isNotBlank()) incoming else existing
    }

    private fun richer(existing: Long?, incoming: Long?): Long? = existing ?: incoming
}
