package com.sjasonp.historylib.feature.manage

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sjasonp.historylib.R
import com.sjasonp.historylib.core.settings.ExpandLevel
import com.sjasonp.historylib.feature.ManageViewModel
import com.sjasonp.historylib.feature.TransferOperation
import com.sjasonp.historylib.feature.TransferUiState
import com.sjasonp.historylib.transfer.HistoryExportFormat
import com.sjasonp.historylib.transfer.HistoryExportSplit
import com.sjasonp.historylib.transfer.ImportFailureCategory
import com.sjasonp.historylib.transfer.TransferPhase
import com.sjasonp.historylib.transfer.TransferSourceKind
import com.sjasonp.historylib.transfer.UriTransferDestination
import com.sjasonp.historylib.transfer.UriTransferSource
import com.sjasonp.historylib.transfer.archive.HlzEncryption
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun ManageScreen(viewModel: ManageViewModel) {
    val context = LocalContext.current
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val syncUnsupported by viewModel.syncUnsupported.collectAsStateWithLifecycle()
    val transferState by viewModel.transferState.collectAsStateWithLifecycle()
    val deletePreview by viewModel.deletePreview.collectAsStateWithLifecycle()
    val storageUsage by viewModel.storageUsage.collectAsStateWithLifecycle()
    val recordTimeRange by viewModel.recordTimeRangeUsec.collectAsStateWithLifecycle()
    val cacheClearedBytes by viewModel.cacheClearedBytes.collectAsStateWithLifecycle()

    var pendingPassword by remember { mutableStateOf<String?>(null) }
    var safariSplit by remember { mutableStateOf(HistoryExportSplit.SINGLE) }
    var selectedExportFormat by remember { mutableStateOf(HistoryExportFormat.HISTORYLIB_ARCHIVE) }
    var currentImportUri by remember { mutableStateOf<Uri?>(null) }
    var currentImportKind by remember { mutableStateOf(TransferSourceKind.FILE) }
    var currentExportUri by remember { mutableStateOf<Uri?>(null) }
    var currentExportFormat by remember { mutableStateOf(HistoryExportFormat.HISTORYLIB_ARCHIVE) }
    var startDateText by remember { mutableStateOf("") }
    var endDateText by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showCacheConfirm by remember { mutableStateOf(false) }
    var showHelp by remember { mutableStateOf(false) }
    var measuringCache by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val parsedDeleteRange = remember(startDateText, endDateText) {
        parseDeleteRange(startDateText, endDateText)
    }
    LaunchedEffect(parsedDeleteRange) {
        if (parsedDeleteRange != null) {
            delay(250)
            viewModel.previewDelete(parsedDeleteRange.first, parsedDeleteRange.second)
        } else {
            viewModel.resetDeletePreview()
        }
    }

    LaunchedEffect(settings.enableDeletion, recordTimeRange) {
        if (settings.enableDeletion && startDateText.isBlank() && endDateText.isBlank()) {
            viewModel.loadRecordTimeRange()
            val range = recordTimeRange
            if (range != null) {
                startDateText = usecToDateText(range.earliestUsec)
                endDateText = usecToDateText(range.latestUsec)
            }
        }
    }

    LaunchedEffect(measuringCache, storageUsage) {
        if (measuringCache && storageUsage != null) {
            measuringCache = false
            showCacheConfirm = true
        }
    }

    val cacheClearedMessage = cacheClearedBytes?.let { stringResource(R.string.manage_cache_cleared, formatBytes(it)) }
    LaunchedEffect(cacheClearedMessage) {
        val message = cacheClearedMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
    }

    val importFileLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            pendingPassword = if (isEncryptedHlz(context, uri)) "" else null
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            currentImportUri = uri
            currentImportKind = TransferSourceKind.FILE
        }
    }
    val importFolderLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            pendingPassword = null
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            currentImportUri = uri
            currentImportKind = TransferSourceKind.DIRECTORY
        }
    }
    val hlzExportLauncher = rememberLauncherForActivityResult(
        CreateDocumentWithMimeTypes(),
    ) { uri ->
        if (uri != null) {
            currentExportFormat = HistoryExportFormat.HISTORYLIB_ARCHIVE
            currentExportUri = uri
            pendingPassword = ""
        }
    }
    val safariExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/zip"),
    ) { uri ->
        if (uri != null) {
            currentExportFormat = HistoryExportFormat.SAFARI_JSON
            currentExportUri = uri
            pendingPassword = null
        }
    }

    if (showHelp) {
        HistoryLibHelperHelpScreen(onBack = { showHelp = false })
        return
    }

    Column(Modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item { SectionTitle(stringResource(R.string.manage_import)) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { importFileLauncher.launch(arrayOf("*/*")) }, Modifier.weight(1f)) {
                        Text(stringResource(R.string.manage_import_file))
                    }
                    Button(onClick = { importFolderLauncher.launch(null) }, Modifier.weight(1f)) {
                        Text(stringResource(R.string.manage_import_folder))
                    }
                }
            }

            item { SectionTitle(stringResource(R.string.manage_export)) }
            item {
                Text(stringResource(R.string.manage_export_format), style = MaterialTheme.typography.bodyLarge)
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = selectedExportFormat == HistoryExportFormat.HISTORYLIB_ARCHIVE,
                        onClick = { selectedExportFormat = HistoryExportFormat.HISTORYLIB_ARCHIVE },
                        label = { Text(stringResource(R.string.manage_export_format_historylib)) },
                    )
                    FilterChip(
                        selected = selectedExportFormat == HistoryExportFormat.SAFARI_JSON,
                        onClick = { selectedExportFormat = HistoryExportFormat.SAFARI_JSON },
                        label = { Text(stringResource(R.string.manage_export_format_safari)) },
                    )
                }
            }
            if (selectedExportFormat == HistoryExportFormat.SAFARI_JSON) {
                item {
                    Text(stringResource(R.string.manage_export_layout), style = MaterialTheme.typography.bodyLarge)
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        HistoryExportSplit.entries.forEach { split ->
                            FilterChip(
                                selected = safariSplit == split,
                                onClick = { safariSplit = split },
                                label = { Text(splitLabel(split)) },
                            )
                        }
                    }
                }
            } else {
                item {
                    Text(
                        stringResource(R.string.manage_export_historylib_note),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            item {
                Button(
                    onClick = {
                        if (selectedExportFormat == HistoryExportFormat.SAFARI_JSON) {
                            safariExportLauncher.launch("History-Safari.zip")
                        } else {
                            hlzExportLauncher.launch(
                                CreateDocumentInput(
                                    fileName = "History.hlz",
                                ),
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text(stringResource(R.string.manage_export_action)) }
            }

            item {
                when (val state = transferState) {
                    is TransferUiState.Running -> {
                        val phaseText = state.progress?.phase?.let { phaseLabel(it) } ?: "-"
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.manage_transfer_running, phaseText), Modifier.weight(1f))
                            TextButton(onClick = viewModel::cancelTransfer) {
                                Text(stringResource(R.string.manage_cancel_transfer))
                            }
                        }
                    }
                    is TransferUiState.ImportDone -> {
                        val imported = state.report.importedRecordCount
                        val skipped = state.report.skippedRecordCount
                        Text(
                            stringResource(
                                R.string.manage_import_done,
                                pluralStringResource(R.plurals.manage_import_done_imported, imported, imported),
                                pluralStringResource(R.plurals.manage_import_done_skipped, skipped, skipped),
                            ),
                        )
                    }
                    is TransferUiState.ImportFailed -> Text(
                        stringResource(
                            R.string.manage_import_failed,
                            state.report.failures.firstOrNull()?.category?.let { importFailureLabel(it) }
                                ?: stringResource(R.string.import_error_invalid_structure),
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                    is TransferUiState.ExportDone -> Text(
                        pluralStringResource(
                            R.plurals.manage_export_done,
                            state.exportedCount,
                            state.exportedCount,
                        ),
                    )
                    is TransferUiState.Error -> Text(
                        stringResource(
                            when (state.operation) {
                                TransferOperation.IMPORT -> R.string.manage_import_error_generic
                                TransferOperation.EXPORT -> R.string.manage_export_error_generic
                            },
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                    TransferUiState.Cancelled -> Text(stringResource(R.string.manage_import_cancelled))
                    TransferUiState.Idle -> Unit
                }
            }

            item { SectionTitle(stringResource(R.string.manage_settings)) }
            item { SettingsToggle(stringResource(R.string.manage_show_visit_time), settings.showVisitTime) { viewModel.updateSettings { it.copy(showVisitTime = !it.showVisitTime) } } }
            item { SettingsToggle(stringResource(R.string.manage_show_site_icons), settings.showSiteIcons) { viewModel.updateSettings { it.copy(showSiteIcons = !it.showSiteIcons) } } }
            item { SettingsToggle(stringResource(R.string.manage_open_link_on_tap), settings.openLinkOnTap) { viewModel.updateSettings { it.copy(openLinkOnTap = !it.openLinkOnTap) } } }
            item { SettingsToggle(stringResource(R.string.manage_enable_deletion), settings.enableDeletion) { viewModel.updateSettings { it.copy(enableDeletion = !it.enableDeletion) } } }
            if (syncUnsupported) {
                item { SectionTitle(stringResource(R.string.manage_sync)) }
                item {
                    Text(
                        stringResource(R.string.manage_sync_unsupported),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            item {
                Column {
                    Text(stringResource(R.string.manage_default_expand), style = MaterialTheme.typography.bodyLarge)
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        ExpandLevel.entries.forEach { level ->
                            FilterChip(
                                selected = settings.defaultExpandTo == level,
                                onClick = { viewModel.updateSettings { it.copy(defaultExpandTo = level) } },
                                label = { Text(expandLevelLabel(level)) },
                            )
                        }
                    }
                }
            }

            item { SectionTitle(stringResource(R.string.manage_cache)) }
            item {
                Button(
                    onClick = {
                        measuringCache = true
                        viewModel.measureCacheUsage()
                    },
                    enabled = !measuringCache,
                ) {
                    Text(
                        if (measuringCache) {
                            stringResource(R.string.manage_cache_measuring)
                        } else {
                            stringResource(R.string.manage_clear_cache)
                        },
                    )
                }
            }

            if (settings.enableDeletion) {
                item { SectionTitle(stringResource(R.string.manage_batch_delete)) }
                item {
                    Text(
                        stringResource(R.string.manage_batch_range_hint),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(
                            value = startDateText,
                            onValueChange = { startDateText = it },
                            label = { Text(stringResource(R.string.manage_batch_start)) },
                            placeholder = { Text(stringResource(R.string.manage_date_placeholder)) },
                            singleLine = true,
                        )
                        OutlinedTextField(
                            value = endDateText,
                            onValueChange = { endDateText = it },
                            label = { Text(stringResource(R.string.manage_batch_end)) },
                            placeholder = { Text(stringResource(R.string.manage_date_placeholder)) },
                            singleLine = true,
                        )
                        if (deletePreview != null) {
                            val count = deletePreview ?: 0L
                            Text(
                                pluralStringResource(
                                    R.plurals.manage_batch_preview,
                                    count.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                                    count,
                                ),
                            )
                        }
                        Button(
                            onClick = { showDeleteConfirm = true },
                            enabled = parsedDeleteRange != null,
                        ) { Text(stringResource(R.string.manage_delete_range)) }
                    }
                }
            }

            item { SectionTitle(stringResource(R.string.manage_help)) }
            item {
                Button(onClick = { showHelp = true }) {
                    Text(stringResource(R.string.manage_help))
                }
            }
        }

        SnackbarHost(snackbarHostState)
    }

    val importUri = currentImportUri
    if (importUri != null && pendingPassword == null) {
        LaunchedEffect(importUri) {
            viewModel.import(
                UriTransferSource(context.contentResolver, importUri, currentImportKind),
                null,
            )
            currentImportUri = null
        }
    }
    if (importUri != null && pendingPassword != null) {
        val importCancelledMessage = stringResource(R.string.manage_import_cancelled)
        PasswordDialog(
            title = stringResource(R.string.manage_password_title),
            requireConfirmation = false,
            onDismiss = {
                scope.launch { snackbarHostState.showSnackbar(importCancelledMessage) }
                currentImportUri = null
                pendingPassword = null
            },
            onConfirm = { password ->
                val source = UriTransferSource(context.contentResolver, importUri, currentImportKind)
                viewModel.import(source, password?.toCharArray())
                currentImportUri = null
                pendingPassword = null
            },
        )
    }

    val exportUri = currentExportUri
    if (exportUri != null) {
        if (currentExportFormat == HistoryExportFormat.HISTORYLIB_ARCHIVE && pendingPassword != null) {
            PasswordDialog(
                title = stringResource(R.string.manage_password_title),
                requireConfirmation = true,
                onDismiss = {
                    currentExportUri = null
                    pendingPassword = null
                },
                onConfirm = { password ->
                    val destination = UriTransferDestination(context.contentResolver, exportUri)
                    viewModel.export(destination, currentExportFormat, safariSplit, password?.toCharArray())
                    currentExportUri = null
                    pendingPassword = null
                },
            )
        } else {
            LaunchedEffect(exportUri) {
                val destination = UriTransferDestination(context.contentResolver, exportUri)
                viewModel.export(destination, currentExportFormat, safariSplit, null)
                currentExportUri = null
            }
        }
    }

    if (showDeleteConfirm && parsedDeleteRange != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text(stringResource(R.string.manage_delete_confirm_title)) },
            text = {
                val count = deletePreview ?: 0L
                Text(
                    pluralStringResource(
                        R.plurals.manage_delete_confirm_body,
                        count.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                        count,
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.batchDelete(parsedDeleteRange.first, parsedDeleteRange.second)
                    showDeleteConfirm = false
                    startDateText = ""
                    endDateText = ""
                }) { Text(stringResource(R.string.manage_delete_confirm)) }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text(stringResource(R.string.common_cancel)) }
            },
        )
    }

    if (showCacheConfirm) {
        val usage = storageUsage
        AlertDialog(
            onDismissRequest = { showCacheConfirm = false },
            title = { Text(stringResource(R.string.manage_cache_clear_title)) },
            text = {
                Text(
                    buildString {
                        appendLine(stringResource(R.string.manage_cache_clearable, formatBytes(usage?.clearableBytes ?: 0L)))
                        appendLine(stringResource(R.string.manage_cache_non_clearable, formatBytes(usage?.nonClearableBytes ?: 0L)))
                        appendLine()
                        appendLine(stringResource(R.string.manage_cache_explanation))
                        appendLine()
                        append(stringResource(R.string.manage_cache_clear_action, formatBytes(usage?.clearableBytes ?: 0L)))
                    },
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.clearCache()
                    showCacheConfirm = false
                }) { Text(stringResource(R.string.manage_clear_cache)) }
            },
            dismissButton = {
                TextButton(onClick = { showCacheConfirm = false }) {
                    Text(stringResource(R.string.common_cancel))
                }
            },
        )
    }
}

@Composable
private fun HistoryLibHelperHelpScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            TextButton(onClick = onBack) {
                Text(stringResource(R.string.manage_back))
            }
            Text(stringResource(R.string.manage_help), style = MaterialTheme.typography.titleMedium)
        }

        Text(stringResource(R.string.help_helper_title), style = MaterialTheme.typography.titleLarge)
        Text(
            stringResource(R.string.help_helper_tagline),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            stringResource(R.string.help_helper_description),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        SectionTitle(stringResource(R.string.help_supported_browsers_title))
        Text(stringResource(R.string.help_supported_browsers_body))

        SectionTitle(stringResource(R.string.help_import_options_title))
        Text(stringResource(R.string.help_import_options_body_1))
        Text(stringResource(R.string.help_import_options_body_2))

        SectionTitle(stringResource(R.string.help_how_it_works_title))
        HelpStep(1, stringResource(R.string.help_step_1))
        HelpStep(2, stringResource(R.string.help_step_2))
        HelpStep(3, stringResource(R.string.help_step_3))
        HelpStep(4, stringResource(R.string.help_step_4))

        SectionTitle(stringResource(R.string.help_privacy_title))
        Text(stringResource(R.string.help_privacy_body))

        Button(
            onClick = {
                runCatching {
                    context.startActivity(
                        Intent(
                            Intent.ACTION_VIEW,
                            Uri.parse("https://prods.notion.site/history-lib-helper"),
                        ),
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.help_download_helper))
        }
    }
}

@Composable
private fun HelpStep(number: Int, text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            text = "$number",
            modifier = Modifier.padding(end = 12.dp),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(text)
    }
}

private fun parseDeleteRange(startText: String, endText: String): Pair<Long, Long>? {
    val zone = ZoneId.systemDefault()
    val formatter = DateTimeFormatter.ISO_LOCAL_DATE
    val start = if (startText.isBlank()) Long.MIN_VALUE else runCatching {
        LocalDate.parse(startText.trim(), formatter).atStartOfDay(zone).toEpochSecond() * 1_000_000L
    }.getOrNull() ?: return null
    val endExclusive = if (endText.isBlank()) Long.MAX_VALUE else runCatching {
        LocalDate.parse(endText.trim(), formatter).plusDays(1).atStartOfDay(zone).toEpochSecond() * 1_000_000L
    }.getOrNull() ?: return null
    if (start != Long.MIN_VALUE && endExclusive != Long.MAX_VALUE && start >= endExclusive) return null
    return start to endExclusive
}

private fun usecToDateText(usec: Long): String {
    val seconds = Math.floorDiv(usec, 1_000_000L)
    return DateTimeFormatter.ISO_LOCAL_DATE.withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochSecond(seconds))
}

private fun isEncryptedHlz(context: android.content.Context, uri: Uri): Boolean {
    return runCatching {
        context.contentResolver.openInputStream(uri)?.use { input ->
            val prefix = input.readNBytes(8)
            prefix.size == 8 && HlzEncryption.isEncrypted(prefix)
        } ?: false
    }.getOrDefault(false)
}

private fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    val kb = bytes / 1024.0
    if (kb < 1024) return String.format(Locale.US, "%.1f KB", kb)
    val mb = kb / 1024.0
    if (mb < 1024) return String.format(Locale.US, "%.1f MB", mb)
    return String.format(Locale.US, "%.2f GB", mb / 1024.0)
}

@Composable
private fun splitLabel(split: HistoryExportSplit): String {
    return when (split) {
        HistoryExportSplit.SINGLE -> stringResource(R.string.manage_export_layout_single)
        HistoryExportSplit.BY_DAY -> stringResource(R.string.manage_export_layout_by_day)
        HistoryExportSplit.BY_MONTH -> stringResource(R.string.manage_export_layout_by_month)
        HistoryExportSplit.BY_YEAR -> stringResource(R.string.manage_export_layout_by_year)
    }
}

@Composable
private fun expandLevelLabel(level: ExpandLevel): String {
    return when (level) {
        ExpandLevel.NONE -> stringResource(R.string.expand_level_none)
        ExpandLevel.YEAR -> stringResource(R.string.expand_level_year)
        ExpandLevel.MONTH -> stringResource(R.string.expand_level_month)
        ExpandLevel.DAY -> stringResource(R.string.expand_level_day)
    }
}

@Composable
private fun phaseLabel(phase: TransferPhase): String {
    return when (phase) {
        TransferPhase.DETECTING -> stringResource(R.string.transfer_phase_detecting)
        TransferPhase.AUTHENTICATING -> stringResource(R.string.transfer_phase_authenticating)
        TransferPhase.READING -> stringResource(R.string.transfer_phase_reading)
        TransferPhase.VALIDATING -> stringResource(R.string.transfer_phase_validating)
        TransferPhase.WRITING -> stringResource(R.string.transfer_phase_writing)
        TransferPhase.MERGING -> stringResource(R.string.transfer_phase_merging)
        TransferPhase.CLEANING_UP -> stringResource(R.string.transfer_phase_cleaning_up)
    }
}

@Composable
private fun importFailureLabel(category: ImportFailureCategory): String = stringResource(
    when (category) {
        ImportFailureCategory.UNRECOGNIZED_INPUT -> R.string.import_error_unrecognized
        ImportFailureCategory.INVALID_STRUCTURE -> R.string.import_error_invalid_structure
        ImportFailureCategory.CHECKSUM_MISMATCH -> R.string.import_error_checksum
        ImportFailureCategory.AUTHENTICATION_FAILED -> R.string.import_error_authentication
        ImportFailureCategory.IO_ERROR -> R.string.import_error_io
        ImportFailureCategory.CANCELLED -> R.string.manage_import_cancelled
    },
)

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun SettingsToggle(label: String, checked: Boolean, onChange: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = { onChange() })
    }
}

@Composable
private fun PasswordDialog(
    title: String,
    requireConfirmation: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (String?) -> Unit,
) {
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    val mismatch = requireConfirmation && password != confirmation
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text(stringResource(R.string.manage_password)) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
                if (requireConfirmation) {
                    OutlinedTextField(
                        value = confirmation,
                        onValueChange = { confirmation = it },
                        label = { Text(stringResource(R.string.manage_password_confirm)) },
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                        isError = mismatch,
                    )
                }
                if (password.isNotEmpty() && password.length < 12) {
                    Text(stringResource(R.string.manage_weak_password), color = MaterialTheme.colorScheme.error)
                }
                if (requireConfirmation) {
                    Text(
                        stringResource(R.string.manage_password_optional_note),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = !mismatch,
                onClick = { onConfirm(password.ifBlank { null }) },
            ) { Text(stringResource(R.string.common_ok)) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) }
        },
    )
}

private data class CreateDocumentInput(
    val fileName: String,
)

private class CreateDocumentWithMimeTypes :
    ActivityResultContract<CreateDocumentInput, Uri?>() {
    override fun createIntent(context: Context, input: CreateDocumentInput): Intent {
        return Intent(Intent.ACTION_CREATE_DOCUMENT)
            .setType("*/*")
            .putExtra(Intent.EXTRA_TITLE, input.fileName)
    }

    override fun parseResult(resultCode: Int, intent: Intent?): Uri? {
        return intent.takeIf { resultCode == Activity.RESULT_OK }?.data
    }
}
