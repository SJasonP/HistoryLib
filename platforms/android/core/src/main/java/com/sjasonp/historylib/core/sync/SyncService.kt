package com.sjasonp.historylib.core.sync

import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.MutableStateFlow

/** Platform-local sync contract defined by shared/specs/sync.md. */
interface SyncService {
    val state: StateFlow<SyncState>

    suspend fun setEnabled(enabled: Boolean)

    suspend fun retry()
}

class UnsupportedSyncService(reason: String) : SyncService {
    override val state: StateFlow<SyncState> = MutableStateFlow(
        SyncState.Unavailable(reason = reason, retryable = false),
    )

    override suspend fun setEnabled(enabled: Boolean) = Unit

    override suspend fun retry() = Unit
}

sealed interface SyncState {
    data object Disabled : SyncState
    data object Activating : SyncState
    data class Active(val lastCompletedAtUsec: Long?) : SyncState
    data class Unavailable(val reason: String, val retryable: Boolean) : SyncState
}
