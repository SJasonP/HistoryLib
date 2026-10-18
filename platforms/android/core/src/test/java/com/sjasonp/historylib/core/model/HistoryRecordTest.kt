package com.sjasonp.historylib.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class HistoryRecordTest {
    @Test
    fun preservesMicrosecondTimestamps() {
        val record = record(visitedAtUsec = 1_725_000_000_123_456)

        assertEquals(1_725_000_000_123_456, record.visitedAtUsec)
    }

    @Test
    fun rejectsInvalidVisitCount() {
        assertThrows(IllegalArgumentException::class.java) {
            record(visitCount = 0)
        }
    }

    private fun record(
        visitedAtUsec: Long = 1,
        visitCount: Int = 1,
    ) = HistoryRecord(
        uniqueKey = "https://example.com/|0|chrome",
        url = "https://example.com/",
        title = "Example",
        visitedAtUsec = visitedAtUsec,
        visitCount = visitCount,
        sourceBrowser = "Chrome",
        sourceFileName = "History.json",
        rawTimeUsec = visitedAtUsec,
        importedAtUsec = 2,
    )
}
