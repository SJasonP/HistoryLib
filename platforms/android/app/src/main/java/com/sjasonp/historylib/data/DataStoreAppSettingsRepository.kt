package com.sjasonp.historylib.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.sjasonp.historylib.core.settings.AppSettings
import com.sjasonp.historylib.core.settings.AppSettingsRepository
import com.sjasonp.historylib.core.settings.ExpandLevel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore by preferencesDataStore(name = "settings")

class DataStoreAppSettingsRepository(private val context: Context) : AppSettingsRepository {
    override val settings: Flow<AppSettings> = context.settingsDataStore.data.map { prefs ->
        AppSettings(
            showVisitTime = prefs[Keys.SHOW_VISIT_TIME] ?: true,
            showSiteIcons = prefs[Keys.SHOW_SITE_ICONS] ?: true,
            defaultExpandTo = ExpandLevel.valueOf(prefs[Keys.DEFAULT_EXPAND_TO] ?: ExpandLevel.DAY.name),
            enableDeletion = prefs[Keys.ENABLE_DELETION] ?: false,
            nearDuplicateToleranceSeconds = prefs[Keys.TOLERANCE_SECONDS] ?: 1,
            syncEnabled = prefs[Keys.SYNC_ENABLED] ?: false,
            openLinkOnTap = prefs[Keys.OPEN_LINK_ON_TAP] ?: true,
        )
    }

    override suspend fun update(transform: (AppSettings) -> AppSettings) {
        context.settingsDataStore.edit { prefs ->
            val current = AppSettings(
                showVisitTime = prefs[Keys.SHOW_VISIT_TIME] ?: true,
                showSiteIcons = prefs[Keys.SHOW_SITE_ICONS] ?: true,
                defaultExpandTo = ExpandLevel.valueOf(prefs[Keys.DEFAULT_EXPAND_TO] ?: ExpandLevel.DAY.name),
                enableDeletion = prefs[Keys.ENABLE_DELETION] ?: false,
                nearDuplicateToleranceSeconds = prefs[Keys.TOLERANCE_SECONDS] ?: 1,
                syncEnabled = prefs[Keys.SYNC_ENABLED] ?: false,
                openLinkOnTap = prefs[Keys.OPEN_LINK_ON_TAP] ?: true,
            )
            val next = transform(current)
            prefs[Keys.SHOW_VISIT_TIME] = next.showVisitTime
            prefs[Keys.SHOW_SITE_ICONS] = next.showSiteIcons
            prefs[Keys.DEFAULT_EXPAND_TO] = next.defaultExpandTo.name
            prefs[Keys.ENABLE_DELETION] = next.enableDeletion
            prefs[Keys.TOLERANCE_SECONDS] = next.nearDuplicateToleranceSeconds
            prefs[Keys.SYNC_ENABLED] = next.syncEnabled
            prefs[Keys.OPEN_LINK_ON_TAP] = next.openLinkOnTap
        }
    }

    private object Keys {
        val SHOW_VISIT_TIME = booleanPreferencesKey("show_visit_time")
        val SHOW_SITE_ICONS = booleanPreferencesKey("show_site_icons")
        val DEFAULT_EXPAND_TO = stringPreferencesKey("default_expand_to")
        val ENABLE_DELETION = booleanPreferencesKey("enable_deletion")
        val TOLERANCE_SECONDS = intPreferencesKey("tolerance_seconds")
        val SYNC_ENABLED = booleanPreferencesKey("sync_enabled")
        val OPEN_LINK_ON_TAP = booleanPreferencesKey("open_link_on_tap")
    }
}
