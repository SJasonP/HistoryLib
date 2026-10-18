package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.archive.HlzChunkIndex
import com.sjasonp.historylib.transfer.archive.HlzManifest
import com.sjasonp.historylib.transfer.archive.JsonLines
import com.sjasonp.historylib.transfer.archive.Sha256
import com.sjasonp.historylib.transfer.archive.ZipSafe
import com.sjasonp.historylib.transfer.archive.ZipValidationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipInputStream

class HistoryLibArchiveImporter {
    private val json = Json { ignoreUnknownKeys = true }

    fun readManifest(input: InputStream): ArchiveMetadata {
        val metadataFiles = mutableMapOf<String, ByteArray>()
        val seen = mutableSetOf<String>()
        var entryCount = 0
        var metadataBytes = 0L
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = ZipSafe.safeEntryName(entry.name)
                if (++entryCount > ZipSafe.MAX_ENTRY_COUNT) throw ZipValidationException("Archive has too many entries")
                if (!seen.add(name)) throw ZipValidationException("Duplicate ZIP entry: $name")
                if (name.endsWith(".json") && !name.startsWith("chunks/")) {
                    val bytes = ZipSafe.readFully(zip, ZipSafe.MAX_METADATA_BYTES)
                    metadataBytes += bytes.size
                    if (metadataBytes > ZipSafe.MAX_TOTAL_METADATA_BYTES) {
                        throw ZipValidationException("Archive metadata exceeds aggregate size limit")
                    }
                    metadataFiles[name] = bytes
                }
                zip.closeEntry()
            }
        }
        val manifestBytes = metadataFiles["manifest.json"]
            ?: throw ZipValidationException("Archive is missing manifest.json")
        val manifest = json.decodeFromString<HlzManifest>(String(manifestBytes, Charsets.UTF_8))
        if (manifest.format != "historylib") throw ZipValidationException("Not a HistoryLib archive")
        if (manifest.format_version != 1) throw ZipValidationException("Unsupported HistoryLib archive version")
        val chunksPath = ZipSafe.safeEntryName(manifest.indexes.chunks)
        val chunksBytes = metadataFiles[chunksPath]
            ?: throw ZipValidationException("Archive is missing $chunksPath")
        val chunks = json.decodeFromString<List<HlzChunkIndex>>(String(chunksBytes, Charsets.UTF_8))
        return ArchiveMetadata(manifest, chunks)
    }

    fun validate(input: InputStream, metadata: ArchiveMetadata) {
        val manifest = metadata.manifest
        val chunks = metadata.chunks
        if (manifest.chunk_count != chunks.size.toLong()) throw ZipValidationException("chunk_count does not match chunks.json")
        val contiguous = chunks.map { it.id }.sorted() == (1..chunks.size.toLong()).toList()
        if (!contiguous) throw ZipValidationException("chunk ids are not contiguous")

        var recordCount = 0L
        val byPath = chunks.associateBy { it.path }
        if (byPath.size != chunks.size) throw ZipValidationException("duplicate chunk paths")
        val found = mutableSetOf<String>()
        val seenEntries = mutableSetOf<String>()
        var entryCount = 0
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = ZipSafe.safeEntryName(entry.name)
                if (++entryCount > ZipSafe.MAX_ENTRY_COUNT) throw ZipValidationException("Archive has too many entries")
                if (!seenEntries.add(name)) throw ZipValidationException("Duplicate ZIP entry: $name")
                if (name.startsWith("chunks/") && name.endsWith(".jsonl") && name !in byPath) {
                    throw ZipValidationException("Archive contains an unindexed chunk: $name")
                }
                val chunk = byPath[name] ?: continue
                found += name
                val digest = MessageDigest.getInstance("SHA-256")
                var count = 0L
                val digestingInput = java.security.DigestInputStream(zip, digest)
                for (line in JsonLines.readBoundedLines(digestingInput)) {
                    if (line.isBlank()) throw ZipValidationException("chunk $name contains a blank record")
                    val obj = try {
                        JsonLines.json.parseToJsonElement(line).jsonObject
                    } catch (_: Exception) {
                        throw ZipValidationException("chunk $name contains malformed JSON")
                    }
                    if (JsonLines.recordFromObject(obj, name, 0L) == null) {
                        throw ZipValidationException("chunk $name contains an invalid record")
                    }
                    count++
                }
                val hash = digest.digest().joinToString("") { "%02x".format(it) }
                if (hash != chunk.sha256) throw ZipValidationException("chunk $name checksum mismatch")
                if (count != chunk.record_count) throw ZipValidationException("chunk $name record count mismatch")
                recordCount += count
                zip.closeEntry()
            }
        }
        if (found.size != chunks.size) throw ZipValidationException("missing chunk files")
        if (recordCount != manifest.record_count) throw ZipValidationException("record_count does not match chunk contents")
    }

    fun records(input: InputStream, metadata: ArchiveMetadata, importTimeUsec: Long): Sequence<HistoryRecord?> = sequence {
        val indexedChunkPaths = metadata.chunks.mapTo(mutableSetOf()) { it.path }
        var importedRecordCount = 0L
        ZipInputStream(input).use { zip ->
            val seen = mutableSetOf<String>()
            var entryCount = 0
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = ZipSafe.safeEntryName(entry.name)
                if (++entryCount > ZipSafe.MAX_ENTRY_COUNT) throw ZipValidationException("Archive has too many entries")
                if (!seen.add(name)) throw ZipValidationException("Duplicate ZIP entry: $name")
                if (!name.startsWith("chunks/") || !name.endsWith(".jsonl")) {
                    zip.closeEntry()
                    continue
                }
                if (name !in indexedChunkPaths) {
                    throw ZipValidationException("Archive contains an unindexed chunk: $name")
                }
                for (line in JsonLines.readBoundedLines(zip)) {
                    if (line.isBlank()) continue
                    val obj = try {
                        JsonLines.json.parseToJsonElement(line).jsonObject
                    } catch (_: Exception) {
                        yield(null)
                        continue
                    }
                    yield(JsonLines.recordFromObject(obj, name, importTimeUsec))
                    importedRecordCount++
                }
                zip.closeEntry()
            }
        }
        if (importedRecordCount != metadata.manifest.record_count) {
            throw ZipValidationException("Imported record count does not match manifest")
        }
    }

}

data class ArchiveMetadata(
    val manifest: HlzManifest,
    val chunks: List<HlzChunkIndex>,
)
