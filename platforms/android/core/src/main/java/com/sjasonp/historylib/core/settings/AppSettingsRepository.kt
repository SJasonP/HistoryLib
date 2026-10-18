package com.sjasonp.historylib.core.settings

import kotlinx.coroutines.flow.Flow

interface AppSettingsRepository {
    val settings: Flow<AppSettings>

    suspend fun update(transform: (AppSettings) -> AppSettings)
}

data class AppSettings(
    val showVisitTime: Boolean = true,
    val showSiteIcons: Boolean = true,
    val defaultExpandTo: ExpandLevel = ExpandLevel.DAY,
    val enableDeletion: Boolean = false,
    val nearDuplicateToleranceSeconds: Int = 1,
    val syncEnabled: Boolean = false,
    val openLinkOnTap: Boolean = true,
) {
    init {
        require(nearDuplicateToleranceSeconds >= 0)
    }
}

enum class ExpandLevel {
    NONE,
    YEAR,
    MONTH,
    DAY,
}
