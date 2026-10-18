package com.sjasonp.historylib.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sjasonp.historylib.core.model.ImportRun
import com.sjasonp.historylib.core.model.ImportRunStatus
import com.sjasonp.historylib.core.model.HistoryQuery
import com.sjasonp.historylib.core.settings.AppSettings
import com.sjasonp.historylib.core.repository.StorageUsage
import com.sjasonp.historylib.di.AppDependencies
import com.sjasonp.historylib.transfer.ExportRequest
import com.sjasonp.historylib.transfer.HistoryExportFormat
import com.sjasonp.historylib.transfer.HistoryExportSplit
import com.sjasonp.historylib.transfer.ImportRequest
import com.sjasonp.historylib.transfer.SecretProvider
import com.sjasonp.historylib.transfer.TransferDestination
import com.sjasonp.historylib.transfer.TransferProgress
import com.sjasonp.historylib.transfer.TransferSource
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class ManageViewModel(private val deps: AppDependencies) : ViewModel() {
    private var transferJob: Job? = null
    val settings: StateFlow<AppSettings> = deps.appSettingsRepository.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppSettings())

    val importRuns: StateFlow<List<ImportRun>> = deps.historyRepository.observeImportRuns()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val syncUnsupported: StateFlow<Boolean> = deps.syncService.state
        .map { it is com.sjasonp.historylib.core.sync.SyncState.Unavailable && !it.retryable }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)

    private val _transferState = MutableStateFlow<TransferUiState>(TransferUiState.Idle)
    val transferState: StateFlow<TransferUiState> = _transferState

    private val _deletePreview = MutableStateFlow<Long?>(null)
    val deletePreview: StateFlow<Long?> = _deletePreview

    private val _storageUsage = MutableStateFlow<StorageUsage?>(null)
    val storageUsage: StateFlow<StorageUsage?> = _storageUsage

    private val _recordTimeRangeUsec = MutableStateFlow<com.sjasonp.historylib.core.repository.RecordTimeRange?>(null)
    val recordTimeRangeUsec: StateFlow<com.sjasonp.historylib.core.repository.RecordTimeRange?> = _recordTimeRangeUsec

    private val _cacheClearedBytes = MutableStateFlow<Long?>(null)
    val cacheClearedBytes: StateFlow<Long?> = _cacheClearedBytes

    fun updateSettings(transform: (AppSettings) -> AppSettings) {
        viewModelScope.launch { deps.appSettingsRepository.update(transform) }
    }

    fun import(source: TransferSource, password: CharArray?) {
        if (transferJob?.isActive == true) return
        transferJob = viewModelScope.launch {
            val startedAt = System.currentTimeMillis() * 1000L
            val runId = deps.historyRepository.recordImportRun(
                ImportRun(
                    startedAtUsec = startedAt,
                    resolvedFormat = "",
                    status = ImportRunStatus.RUNNING,
                ),
            )
            _transferState.value = TransferUiState.Running(null)
            val provider = SecretProvider { password }
            val report = try {
                deps.historyImporter.importHistory(
                    ImportRequest(source = source, archivePassword = provider),
                ) { progress -> _transferState.value = TransferUiState.Running(progress) }
            } catch (e: CancellationException) {
                withContext(NonCancellable) {
                    deps.historyRepository.recordImportRun(
                        ImportRun(
                            id = runId,
                            startedAtUsec = startedAt,
                            finishedAtUsec = System.currentTimeMillis() * 1000L,
                            resolvedFormat = "",
                            status = ImportRunStatus.CANCELLED,
                        ),
                    )
                    _transferState.value = TransferUiState.Cancelled
                }
                return@launch
            } catch (_: Exception) {
                withContext(NonCancellable) {
                    deps.historyRepository.recordImportRun(
                        ImportRun(
                            id = runId,
                            startedAtUsec = startedAt,
                            finishedAtUsec = System.currentTimeMillis() * 1000L,
                            resolvedFormat = "",
                            status = ImportRunStatus.FAILED,
                            failureMessage = "Import operation failed",
                        ),
                    )
                }
                _transferState.value = TransferUiState.Error(TransferOperation.IMPORT)
                return@launch
            }
            deps.historyRepository.recordImportRun(
                ImportRun(
                    id = runId,
                    startedAtUsec = startedAt,
                    finishedAtUsec = System.currentTimeMillis() * 1000L,
                    resolvedFormat = report.resolvedFormat?.name.orEmpty(),
                    status = when {
                        report.cancelled -> ImportRunStatus.CANCELLED
                        report.failures.isNotEmpty() && report.importedRecordCount == 0 -> ImportRunStatus.FAILED
                        else -> ImportRunStatus.COMPLETED
                    },
                    scannedFileCount = report.scannedFileCount,
                    validFileCount = report.validFileCount,
                    importedRecordCount = report.importedRecordCount,
                    skippedRecordCount = report.skippedRecordCount,
                    failureMessage = report.failures.firstOrNull()?.userMessage,
                ),
            )
            _transferState.value = if (report.cancelled || report.failures.isNotEmpty()) {
                TransferUiState.ImportFailed(report)
            } else {
                TransferUiState.ImportDone(report)
            }
        }.also { job -> job.invokeOnCompletion { password?.fill('\u0000') } }
    }

    fun export(destination: TransferDestination, format: HistoryExportFormat, split: HistoryExportSplit, password: CharArray?) {
        if (transferJob?.isActive == true) return
        transferJob = viewModelScope.launch {
            _transferState.value = TransferUiState.Running(null)
            val provider = SecretProvider { password }
            try {
                val report = deps.historyExporter.export(
                    ExportRequest(
                        format = format,
                        destination = destination,
                        split = split,
                        archivePassword = provider,
                    ),
                ) { progress -> _transferState.value = TransferUiState.Running(progress) }
                _transferState.value = TransferUiState.ExportDone(report.exportedRecordCount)
            } catch (_: CancellationException) {
                _transferState.value = TransferUiState.Cancelled
            } catch (_: Exception) {
                _transferState.value = TransferUiState.Error(TransferOperation.EXPORT)
            }
        }.also { job -> job.invokeOnCompletion { password?.fill('\u0000') } }
    }

    fun cancelTransfer() {
        transferJob?.cancel()
    }

    fun clearCache() {
        viewModelScope.launch {
            val removedBytes = deps.faviconRepository.cacheUsageBytes()
            deps.faviconRepository.clear()
            _storageUsage.value = StorageUsage(
                clearableBytes = 0L,
                nonClearableBytes = _storageUsage.value?.nonClearableBytes ?: 0L,
            )
            _cacheClearedBytes.value = removedBytes
        }
    }

    fun measureCacheUsage() {
        viewModelScope.launch {
            _storageUsage.value = deps.faviconRepository.storageUsage()
        }
    }

    fun loadRecordTimeRange() {
        viewModelScope.launch {
            _recordTimeRangeUsec.value = deps.historyRepository.recordTimeRangeUsec()
        }
    }

    fun batchDelete(startUsecInclusive: Long, endUsecExclusive: Long) {
        viewModelScope.launch {
            deps.historyRepository.deleteRange(startUsecInclusive, endUsecExclusive)
            _deletePreview.value = null
        }
    }

    fun previewDelete(startUsecInclusive: Long, endUsecExclusive: Long) {
        viewModelScope.launch {
            _deletePreview.value = deps.historyRepository.count(
                HistoryQuery(startUsecInclusive = startUsecInclusive, endUsecExclusive = endUsecExclusive),
            )
        }
    }

    fun resetDeletePreview() {
        _deletePreview.value = null
    }

}

sealed interface TransferUiState {
    data object Idle : TransferUiState
    data class Running(val progress: TransferProgress?) : TransferUiState
    data class ImportDone(val report: com.sjasonp.historylib.transfer.ImportReport) : TransferUiState
    data class ImportFailed(val report: com.sjasonp.historylib.transfer.ImportReport) : TransferUiState
    data class ExportDone(val exportedCount: Int) : TransferUiState
    data class Error(val operation: TransferOperation) : TransferUiState
    data object Cancelled : TransferUiState
}

enum class TransferOperation { IMPORT, EXPORT }
