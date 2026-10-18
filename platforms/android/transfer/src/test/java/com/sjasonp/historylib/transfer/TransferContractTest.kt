package com.sjasonp.historylib.transfer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class TransferContractTest {
    @Test
    fun indeterminateProgressDoesNotPretendToHaveATotal() {
        assertFalse(TransferProgress(TransferPhase.DETECTING).isDeterminate)
    }

    @Test
    fun importReportRejectsMoreValidFilesThanScannedFiles() {
        assertThrows(IllegalArgumentException::class.java) {
            ImportReport(
                resolvedFormat = HistoryImportFormat.SAFARI,
                scannedFileCount = 1,
                validFileCount = 2,
                importedRecordCount = 0,
                skippedRecordCount = 0,
            )
        }
    }
}
