package com.sjasonp.historylib.di

import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.repository.FaviconRepository
import com.sjasonp.historylib.core.settings.AppSettingsRepository
import com.sjasonp.historylib.transfer.HistoryExporter
import com.sjasonp.historylib.transfer.HistoryImporter
import com.sjasonp.historylib.core.sync.SyncService

/**
 * Application composition boundary. Concrete implementations belong in :app
 * adapters and are wired here; screens and view models consume these contracts.
 */
interface HistoryLibDependencies {
    val historyRepository: HistoryRepository
    val appSettingsRepository: AppSettingsRepository
    val faviconRepository: FaviconRepository
    val historyImporter: HistoryImporter
    val historyExporter: HistoryExporter
    val syncService: SyncService
}
