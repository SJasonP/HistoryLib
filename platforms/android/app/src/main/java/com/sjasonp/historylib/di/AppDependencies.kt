package com.sjasonp.historylib.di

import android.content.Context
import com.sjasonp.historylib.core.repository.FaviconRepository
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.settings.AppSettingsRepository
import com.sjasonp.historylib.data.DataStoreAppSettingsRepository
import com.sjasonp.historylib.data.HistoryLibDatabase
import com.sjasonp.historylib.data.HttpFaviconRepository
import com.sjasonp.historylib.data.RoomHistoryRepository
import com.sjasonp.historylib.transfer.DefaultHistoryExporter
import com.sjasonp.historylib.transfer.DefaultHistoryImporter
import com.sjasonp.historylib.transfer.HistoryExporter
import com.sjasonp.historylib.transfer.HistoryImporter
import com.sjasonp.historylib.core.sync.SyncService
import com.sjasonp.historylib.core.sync.UnsupportedSyncService
import com.sjasonp.historylib.transfer.FileTransferScratch

class AppDependencies(context: Context) : HistoryLibDependencies {
    private val appContext = context.applicationContext
    private val database = HistoryLibDatabase.build(appContext)

    override val appSettingsRepository: AppSettingsRepository = DataStoreAppSettingsRepository(appContext)
    override val historyRepository: HistoryRepository = RoomHistoryRepository(
        dao = database.historyDao(),
        settingsRepository = appSettingsRepository,
    )
    override val faviconRepository: FaviconRepository = HttpFaviconRepository(appContext)
    override val historyImporter: HistoryImporter = DefaultHistoryImporter(
        repository = historyRepository,
        scratch = FileTransferScratch(appContext),
    )
    override val historyExporter: HistoryExporter = DefaultHistoryExporter(historyRepository, appVersion())
    override val syncService: SyncService = UnsupportedSyncService("Sync is not available on Android 1.4")

    private fun appVersion(): String {
        return try {
            appContext.packageManager.getPackageInfo(appContext.packageName, 0).versionName ?: "1.4"
        } catch (_: Exception) {
            "1.4"
        }
    }
}
