package com.sjasonp.historylib

import org.junit.Assert.assertEquals
import org.junit.Test

class AppDestinationTest {
    @Test
    fun topLevelDestinationsMatchTheProductStructure() {
        assertEquals(
            listOf("SUMMARY", "LIBRARY", "MANAGE"),
            AppDestination.entries.map(AppDestination::name),
        )
    }
}
