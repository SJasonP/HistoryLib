package com.sjasonp.historylib.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.ImportRunStatus
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryDaoTest {
    private lateinit var database: HistoryLibDatabase
    private lateinit var dao: HistoryDao

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, HistoryLibDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = database.historyDao()
    }

    @After
    fun tearDown() = database.close()

    @Test
    fun pagingAndSearchPreserveNewestFirstContainsSemantics() = runBlocking {
        dao.insertAll(
            listOf(
                entity("https://example.com/older", "Alpha", 1_000_000L),
                entity("https://example.com/newer", "Beta needle", 3_000_000L),
                entity("https://other.test/middle-needle", "Gamma", 2_000_000L),
            ),
        )

        assertEquals(listOf(3_000_000L, 2_000_000L), dao.loadPage(offset = 0, limit = 2).map { it.visitedAtUsec })
        assertEquals(
            listOf(3_000_000L, 2_000_000L),
            dao.loadSearchPage("%needle%", offset = 0, limit = 10).map { it.visitedAtUsec },
        )
    }

    @Test
    fun interruptedImportRunIsRecoveredAsCancelled() = runBlocking {
        val id = dao.insertImportRun(
            ImportRunEntity.from(
                ImportRun(
                    startedAtUsec = 10L,
                    resolvedFormat = "",
                    status = ImportRunStatus.RUNNING,
                ),
            ),
        )

        assertEquals(1, dao.cancelInterruptedImportRuns(20L))
        val recovered = dao.observeImportRuns().first().single { it.id == id }
        assertEquals(ImportRunStatus.CANCELLED.name, recovered.status)
        assertEquals(20L, recovered.finishedAtUsec)
    }

    private fun entity(url: String, title: String, visitedAtUsec: Long): HistoryRecordEntity =
        HistoryRecordEntity.from(
            HistoryRecord(
                uniqueKey = "$url|$visitedAtUsec",
                url = url,
                title = title,
                visitedAtUsec = visitedAtUsec,
                visitCount = 1,
                sourceBrowser = "test",
                sourceFileName = "fixture.json",
                rawTimeUsec = visitedAtUsec,
                importedAtUsec = visitedAtUsec,
            ),
        )
}
