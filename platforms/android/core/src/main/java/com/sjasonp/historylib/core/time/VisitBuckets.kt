package com.sjasonp.historylib.core.time

import com.sjasonp.historylib.core.model.DayCount
import com.sjasonp.historylib.core.model.HistoryRecord
import java.time.Instant
import java.time.ZoneId

data class VisitBucket(
    val year: Int,
    val month: Int,
    val day: Int,
    val records: List<HistoryRecord>,
)

object VisitBuckets {
    fun byDay(records: List<HistoryRecord>, zoneId: ZoneId): List<VisitBucket> {
        return records
            .groupBy { it.visitedAtUsec.toLocalDate(zoneId) }
            .map { (date, dayRecords) ->
                VisitBucket(
                    year = date.year,
                    month = date.monthValue,
                    day = date.dayOfMonth,
                    records = dayRecords.sortedByDescending { it.visitedAtUsec },
                )
            }
            .sortedWith(compareByDescending<VisitBucket> { it.year }
                .thenByDescending { it.month }
                .thenByDescending { it.day })
    }

    fun toDayCounts(records: List<HistoryRecord>, zoneId: ZoneId): List<DayCount> {
        return records
            .groupBy { it.visitedAtUsec.toLocalDate(zoneId) }
            .map { (date, dayRecords) ->
                DayCount(
                    year = date.year,
                    month = date.monthValue,
                    day = date.dayOfMonth,
                    recordCount = dayRecords.size.toLong(),
                )
            }
            .sortedWith(compareByDescending<DayCount> { it.year }
                .thenByDescending { it.month }
                .thenByDescending { it.day })
    }

    private fun Long.toLocalDate(zoneId: ZoneId): java.time.LocalDate {
        val seconds = Math.floorDiv(this, 1_000_000L)
        val micros = (this % 1_000_000L).toInt()
        return Instant.ofEpochSecond(seconds, micros * 1000L).atZone(zoneId).toLocalDate()
    }
}
