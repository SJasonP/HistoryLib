package com.sjasonp.historylib.transfer

import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.transfer.archive.HlzEncryption
import com.sjasonp.historylib.transfer.archive.HlzEncryptionException
import com.sjasonp.historylib.transfer.archive.ZipSafe
import com.sjasonp.historylib.transfer.archive.ZipValidationException
import com.sjasonp.historylib.transfer.import.ChromeTakeoutImporter
import com.sjasonp.historylib.transfer.import.ContentDetector
import com.sjasonp.historylib.transfer.import.HistoryLibArchiveImporter
import com.sjasonp.historylib.transfer.import.SafariImporter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.SequenceInputStream
import java.io.InputStream
import java.util.zip.ZipInputStream
import kotlin.coroutines.coroutineContext

class DefaultHistoryImporter(
    private val repository: HistoryRepository,
    private val scratch: TransferScratch,
    private val clockUsec: () -> Long = { System.currentTimeMillis() * 1000L },
) : HistoryImporter {
    private data class DirectoryTraversalState(
        val visited: MutableSet<String> = mutableSetOf(),
        var nodes: Long = 0,
    )
    private val safariImporter = SafariImporter()
    private val chromeImporter = ChromeTakeoutImporter()
    private val archiveImporter = HistoryLibArchiveImporter()

    override suspend fun importHistory(
        request: ImportRequest,
        onProgress: suspend (TransferProgress) -> Unit,
    ): ImportReport = withContext(Dispatchers.IO) {
        val startedAt = clockUsec()
        val accumulator = ImportAccumulator()
        var resolvedFormat: HistoryImportFormat? = null
        try {
            onProgress(TransferProgress(TransferPhase.DETECTING))
            resolvedFormat = when (request.source.kind) {
                TransferSourceKind.FILE -> importFile(request, accumulator, onProgress, startedAt)
                TransferSourceKind.DIRECTORY -> importDirectory(request, accumulator, onProgress, startedAt)
            }
        } catch (e: CancellationException) {
            accumulator.cancelled = true
            throw e
        } catch (e: Exception) {
            accumulator.failures += ImportFailure(
                displayName = request.source.displayName,
                category = when {
                    e is HlzEncryptionException -> ImportFailureCategory.AUTHENTICATION_FAILED
                    e is ZipValidationException && e.message?.contains("checksum", ignoreCase = true) == true ->
                        ImportFailureCategory.CHECKSUM_MISMATCH
                    e is ZipValidationException || e is kotlinx.serialization.SerializationException ->
                        ImportFailureCategory.INVALID_STRUCTURE
                    else -> ImportFailureCategory.IO_ERROR
                },
                userMessage = when (e) {
                    is HlzEncryptionException -> "Archive authentication failed"
                    else -> e.message ?: "Import failed"
                },
            )
        } finally {
            if (accumulator.inserted > 0 || accumulator.merged > 0) {
                withContext(NonCancellable) { repository.refreshDerivedData() }
            }
        }

        ImportReport(
            resolvedFormat = resolvedFormat,
            scannedFileCount = accumulator.scanned,
            validFileCount = accumulator.valid,
            importedRecordCount = accumulator.inserted,
            skippedRecordCount = accumulator.merged + accumulator.skippedInvalid,
            failures = accumulator.failures,
            cancelled = accumulator.cancelled,
        )
    }

    private suspend fun importFile(
        request: ImportRequest,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
        importTimeUsec: Long,
    ): HistoryImportFormat? {
        val source = request.source
        accumulator.scanned++
        val prefix = source.withInputStream { stream -> stream.readNBytes(PREFIX_BYTES) }

        if (HlzEncryption.isEncrypted(prefix)) {
            val password = request.archivePassword?.requestSecret()
            if (password == null) {
                accumulator.failures += ImportFailure(
                    source.displayName,
                    ImportFailureCategory.AUTHENTICATION_FAILED,
                    "Password required",
                )
                return HistoryImportFormat.HISTORYLIB_ARCHIVE
            }
            scratch.withTempFile(".hlz") { file ->
                source.withInputStream { encrypted ->
                    file.newOutputStream().use { plain -> HlzEncryption.decryptTo(encrypted, plain, password) }
                }
                importHistoryLibZip(
                    { block -> useStream(file.newInputStream(), block) },
                    accumulator,
                    onProgress,
                    importTimeUsec,
                )
            }
            return HistoryImportFormat.HISTORYLIB_ARCHIVE
        }

        if (ZipSafe.isZip(prefix)) {
            val detected = source.withInputStream { ContentDetector.sniffZipEntries(it) }
            return when (detected) {
                HistoryImportFormat.HISTORYLIB_ARCHIVE -> {
                    importHistoryLibZip({ block -> source.withInputStream { block(it) } }, accumulator, onProgress, importTimeUsec)
                    HistoryImportFormat.HISTORYLIB_ARCHIVE
                }
                HistoryImportFormat.SAFARI, HistoryImportFormat.CHROME_TAKEOUT -> {
                    importJsonZip(source, accumulator, onProgress, importTimeUsec)
                    detected
                }
                null -> {
                    accumulator.unknown(source.displayName)
                    null
                }
            }
        }

        val jsonFormat = ContentDetector.detectJson(String(prefix, Charsets.UTF_8))
        if (jsonFormat == null) {
            accumulator.unknown(source.displayName)
            return null
        }
        source.withInputStream { stream ->
            mergeSequence(parseJson(jsonFormat, stream, source.displayName, importTimeUsec), accumulator, onProgress)
        }
        accumulator.valid++
        return jsonFormat
    }

    private suspend fun importDirectory(
        request: ImportRequest,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
        importTimeUsec: Long,
    ): HistoryImportFormat? {
        val format = importDirectorySource(
            request.source,
            accumulator,
            onProgress,
            importTimeUsec,
            DirectoryTraversalState(),
            depth = 0,
        )
        if (format == null && accumulator.failures.isEmpty()) accumulator.unknown(request.source.displayName)
        return format
    }

    private suspend fun importDirectorySource(
        source: TransferSource,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
        importTimeUsec: Long,
        traversal: DirectoryTraversalState,
        depth: Int,
    ): HistoryImportFormat? {
        if (depth > MAX_DIRECTORY_DEPTH) throw ZipValidationException("Directory tree is too deep")
        if (!traversal.visited.add(source.traversalIdentity)) {
            throw ZipValidationException("Directory tree contains a cycle")
        }
        var detectedFormat: HistoryImportFormat? = null
        for (child in source.children()) {
            coroutineContext.ensureActive()
            traversal.nodes++
            if (traversal.nodes > MAX_DIRECTORY_NODES) {
                throw ZipValidationException("Directory tree contains too many items")
            }
            if (child.kind == TransferSourceKind.DIRECTORY) {
                val nested = importDirectorySource(
                    child, accumulator, onProgress, importTimeUsec, traversal, depth + 1,
                )
                if (detectedFormat == null) detectedFormat = nested
                continue
            }
            if (!child.displayName.endsWith(".json", ignoreCase = true)) continue
            accumulator.scanned++
            val prefix = child.withInputStream { it.readNBytes(PREFIX_BYTES) }
            val format = ContentDetector.detectJson(String(prefix, Charsets.UTF_8))
            if (format == null) {
                accumulator.unknown(child.displayName)
                continue
            }
            if (detectedFormat == null) detectedFormat = format
            child.withInputStream { stream ->
                mergeSequence(parseJson(format, stream, child.displayName, importTimeUsec), accumulator, onProgress)
            }
            accumulator.valid++
        }
        return detectedFormat
    }

    private suspend fun importJsonZip(
        source: TransferSource,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
        importTimeUsec: Long,
    ) {
        source.withInputStream { stream ->
            ZipInputStream(stream).use { zip ->
                val seen = mutableSetOf<String>()
                var entryCount = 0
                while (true) {
                    coroutineContext.ensureActive()
                    val entry = zip.nextEntry ?: break
                    val name = ZipSafe.safeEntryName(entry.name)
                    if (++entryCount > ZipSafe.MAX_ENTRY_COUNT) throw ZipValidationException("Archive has too many entries")
                    if (!seen.add(name)) throw ZipValidationException("Duplicate ZIP entry: $name")
                    if (!name.endsWith(".json", ignoreCase = true)) {
                        zip.closeEntry()
                        continue
                    }
                    val prefixBytes = zip.readNBytes(PREFIX_BYTES)
                    val detected = ContentDetector.detectJson(String(prefixBytes, Charsets.UTF_8))
                    if (detected != null) {
                        val combined = SequenceInputStream(ByteArrayInputStream(prefixBytes), zip)
                        mergeSequence(parseJson(detected, combined, name, importTimeUsec), accumulator, onProgress)
                    }
                    zip.closeEntry()
                }
            }
        }
        accumulator.valid++
    }

    private suspend fun importHistoryLibZip(
        openAndUse: StreamScope,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
        importTimeUsec: Long,
    ) {
        var metadata: com.sjasonp.historylib.transfer.import.ArchiveMetadata? = null
        openAndUse { stream -> metadata = archiveImporter.readManifest(stream) }
        openAndUse { stream -> archiveImporter.validate(stream, metadata!!) }
        accumulator.valid++
        openAndUse { stream ->
            mergeSequence(archiveImporter.records(stream, metadata!!, importTimeUsec), accumulator, onProgress)
        }
    }

    private fun parseJson(
        format: HistoryImportFormat,
        input: InputStream,
        sourceFileName: String,
        importTimeUsec: Long,
    ): Sequence<HistoryRecord?> {
        return when (format) {
            HistoryImportFormat.SAFARI -> safariImporter.parse(input, sourceFileName, importTimeUsec)
            HistoryImportFormat.CHROME_TAKEOUT -> chromeImporter.parse(input, sourceFileName, importTimeUsec)
            HistoryImportFormat.HISTORYLIB_ARCHIVE -> emptySequence()
        }
    }

    private suspend fun mergeSequence(
        records: Sequence<HistoryRecord?>,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
    ) {
        var batch = mutableListOf<HistoryRecord>()
        for (record in records) {
            coroutineContext.ensureActive()
            if (record == null) {
                accumulator.skippedInvalid++
                continue
            }
            batch += record
            if (batch.size >= MERGE_BATCH_SIZE) {
                flushBatch(batch, accumulator, onProgress)
                batch = mutableListOf()
            }
        }
        flushBatch(batch, accumulator, onProgress)
    }

    private suspend fun flushBatch(
        batch: List<HistoryRecord>,
        accumulator: ImportAccumulator,
        onProgress: suspend (TransferProgress) -> Unit,
    ) {
        if (batch.isEmpty()) return
        onProgress(TransferProgress(TransferPhase.MERGING, accumulator.inserted.toLong(), null))
        val result = repository.merge(batch)
        accumulator.inserted += result.insertedCount
        accumulator.merged += result.mergedCount
    }

    private suspend fun useStream(input: InputStream, block: suspend (InputStream) -> Unit) {
        try {
            block(input)
        } finally {
            input.close()
        }
    }

    private class ImportAccumulator {
        var scanned = 0
        var valid = 0
        var inserted = 0
        var merged = 0
        var skippedInvalid = 0
        var cancelled = false
        val failures = mutableListOf<ImportFailure>()

        fun unknown(displayName: String) {
            failures += ImportFailure(
                displayName = displayName,
                category = ImportFailureCategory.UNRECOGNIZED_INPUT,
                userMessage = "Unsupported input",
            )
        }
    }

    companion object {
        private const val PREFIX_BYTES = 65_536
        private const val MERGE_BATCH_SIZE = 500
        private const val MAX_DIRECTORY_DEPTH = 256
        private const val MAX_DIRECTORY_NODES = 1_000_000L
    }
}

private typealias StreamScope = suspend (suspend (InputStream) -> Unit) -> Unit
