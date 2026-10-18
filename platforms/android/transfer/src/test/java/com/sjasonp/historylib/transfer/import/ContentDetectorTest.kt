package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.transfer.HistoryImportFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ContentDetectorTest {
    @Test
    fun detectsChromeOnlyFromATopLevelArrayKey() {
        assertEquals(
            HistoryImportFormat.CHROME_TAKEOUT,
            ContentDetector.detectJson("""{"Browser History":[]}"""),
        )
        assertNull(ContentDetector.detectJson("""{"title":"Browser History","items":[]}"""))
    }

    @Test
    fun detectsSafariFromStructuredMetadata() {
        assertEquals(
            HistoryImportFormat.SAFARI,
            ContentDetector.detectJson(
                """{"metadata":{"browser_name":"Safari","data_type":"history"},"history":[]}""",
            ),
        )
    }

    @Test
    fun rejectsScatteredSafariWords() {
        assertNull(
            ContentDetector.detectJson(
                """{"metadata":"Safari","browser_name":"Safari","data_type":"history","history":[]}""",
            ),
        )
    }
}
