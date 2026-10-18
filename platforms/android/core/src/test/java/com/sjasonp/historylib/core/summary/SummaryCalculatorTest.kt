package com.sjasonp.historylib.core.summary

import com.sjasonp.historylib.core.model.HistoryRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class SummaryCalculatorTest {
    @Test
    fun countsStoredRecordsRatherThanVisitCount() {
        val records = listOf(
            record("https://a.example/", 1_700_000_000_000_000L, visitCount = 3),
            record("https://b.example/", 1_700_000_000_000_001L, visitCount = 7),
        )
        val summary = SummaryCalculator.compute(records, generatedAtUsec = 2L)
        assertEquals(2L, summary.totalRecords)
        assertEquals(1L, summary.topSites.single { it.host == "a.example" }.count)
    }

    @Test
    fun emptyDatasetHasZeroAverages() {
        val summary = SummaryCalculator.compute(emptyList(), generatedAtUsec = 2L)
        assertEquals(0L, summary.totalRecords)
        assertEquals(0.0, summary.averagePerDay, 0.0)
        assertTrue(summary.topSites.isEmpty())
    }

    @Test
    fun daySpanUsesTheUsersTimeZone() {
        val records = listOf(
            record("https://a.example/", 1_704_067_000_000_000L, 1),
            record("https://b.example/", 1_704_070_600_000_000L, 1),
        )
        val summary = SummaryCalculator.compute(records, 2L, ZoneId.of("Asia/Shanghai"))
        assertEquals(2.0, summary.averagePerDay, 0.0)
    }

    private fun record(url: String, visitedAtUsec: Long, visitCount: Int) = HistoryRecord(
        uniqueKey = "$url|${Math.floorDiv(visitedAtUsec, 1_000_000L)}|chrome",
        url = url,
        title = "t",
        visitedAtUsec = visitedAtUsec,
        visitCount = visitCount,
        sourceBrowser = "Chrome",
        sourceFileName = "History.json",
        rawTimeUsec = visitedAtUsec,
        importedAtUsec = 2L,
    )
}
