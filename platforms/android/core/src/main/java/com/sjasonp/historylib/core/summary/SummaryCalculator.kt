package com.sjasonp.historylib.core.summary

import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.core.model.TopSite
import java.time.Instant
import java.time.ZoneId

object SummaryCalculator {
    fun compute(
        records: List<HistoryRecord>,
        generatedAtUsec: Long,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): SummarySnapshot {
        if (records.isEmpty()) {
            return empty(generatedAtUsec)
        }

        val total = records.size.toLong()
        val earliest = records.minOf { it.visitedAtUsec }
        val latest = records.maxOf { it.visitedAtUsec }

        val topSites = records
            .map { it.hostOrDefault() }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .take(10)
            .map { TopSite(host = it.key, count = it.value.toLong()) }

        return build(total, earliest, latest, topSites, generatedAtUsec, zoneId)
    }

    fun compute(
        totalRecords: Long,
        earliestVisitUsec: Long,
        latestVisitUsec: Long,
        topSites: List<TopSite>,
        generatedAtUsec: Long,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): SummarySnapshot {
        return build(totalRecords, earliestVisitUsec, latestVisitUsec, topSites, generatedAtUsec, zoneId)
    }

    fun empty(generatedAtUsec: Long): SummarySnapshot {
        return SummarySnapshot(
            totalRecords = 0,
            averagePerDay = 0.0,
            averagePerMonth = 0.0,
            averagePerYear = 0.0,
            earliestVisitUsec = null,
            latestVisitUsec = null,
            generatedAtUsec = generatedAtUsec,
            topSites = emptyList(),
        )
    }

    private fun build(
        total: Long,
        earliest: Long,
        latest: Long,
        topSites: List<TopSite>,
        generatedAtUsec: Long,
        zoneId: ZoneId,
    ): SummarySnapshot {
        val earliestDay = earliest.toLocalDate(zoneId)
        val latestDay = latest.toLocalDate(zoneId)
        val daySpan = earliestDay.toEpochDay()..latestDay.toEpochDay()
        val inclusiveDays = daySpan.count().toLong()
        val monthSpan = inclusiveMonths(earliestDay, latestDay)
        val yearSpan = latestDay.year - earliestDay.year + 1L

        return SummarySnapshot(
            totalRecords = total,
            averagePerDay = total.toDouble() / inclusiveDays,
            averagePerMonth = total.toDouble() / monthSpan,
            averagePerYear = total.toDouble() / yearSpan,
            earliestVisitUsec = earliest,
            latestVisitUsec = latest,
            generatedAtUsec = generatedAtUsec,
            topSites = topSites,
        )
    }

    private fun Long.toLocalDate(zoneId: ZoneId): java.time.LocalDate =
        Instant.ofEpochSecond(Math.floorDiv(this, 1_000_000L), (this % 1_000_000L) * 1000L)
            .atZone(zoneId)
            .toLocalDate()

    private fun inclusiveMonths(start: java.time.LocalDate, end: java.time.LocalDate): Long {
        val startMonths = start.year.toLong() * 12 + start.monthValue
        val endMonths = end.year.toLong() * 12 + end.monthValue
        return endMonths - startMonths + 1
    }

    private fun HistoryRecord.hostOrDefault(): String {
        return com.sjasonp.historylib.core.dedup.UrlNormalizer.hostOrDefault(url)
    }
}
