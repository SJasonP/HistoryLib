package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.transfer.HistoryImportFormat
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SharedImportFixturesTest {
    @Test
    fun detectsSharedSafariFixture() {
        assertEquals(HistoryImportFormat.SAFARI, ContentDetector.detectJson(fixture("import/safari-valid.json")))
    }

    @Test
    fun detectsSharedChromeFixture() {
        assertEquals(HistoryImportFormat.CHROME_TAKEOUT, ContentDetector.detectJson(fixture("import/chrome-valid.json")))
    }

    @Test
    fun rejectsSharedUnknownFixture() {
        assertNull(ContentDetector.detectJson(fixture("import/unknown-browser-history-string.json")))
    }

    private fun fixture(path: String): String {
        return File(requireNotNull(System.getProperty("historylib.sharedFixtures")), path).readText()
    }
}
