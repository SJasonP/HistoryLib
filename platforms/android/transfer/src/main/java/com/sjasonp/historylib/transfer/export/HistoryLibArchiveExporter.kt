package com.sjasonp.historylib.transfer.export

import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.archive.HlzChunkIndex
import com.sjasonp.historylib.transfer.archive.HlzEncryption
import com.sjasonp.historylib.transfer.archive.HlzIndexes
import com.sjasonp.historylib.transfer.archive.HlzManifest
import com.sjasonp.historylib.transfer.archive.HlzTimeRange
import com.sjasonp.historylib.transfer.archive.JsonLines
import com.sjasonp.historylib.transfer.archive.Sha256
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.time.Instant
import java.time.ZoneOffset
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class HistoryLibArchiveExporter {
    suspend fun exportTo(
        forEachBatch: suspend (suspend (List<HistoryRecord>) -> Unit) -> Unit,
        out: OutputStream,
        appVersion: String,
        exportTimeUsec: Long,
        password: CharArray?,
    ): Long {
        val target = if (password == null) out else HlzEncryption.encryptingOutputStream(out, password)
        var totalRecords = 0L
        var minTs = Long.MAX_VALUE
        var maxTs = Long.MIN_VALUE
        val dayCounts = sortedMapOf<String, Long>()

        forEachBatch { batch ->
            batch.forEach { record ->
                totalRecords++
                minTs = minOf(minTs, record.visitedAtUsec)
                maxTs = maxOf(maxTs, record.visitedAtUsec)
                dayCounts.merge(dayKey(record.visitedAtUsec), 1, Long::plus)
            }
        }

        val chunkCount = if (totalRecords == 0L) 0L else (totalRecords + CHUNK_TARGET_RECORDS - 1) / CHUNK_TARGET_RECORDS

        ZipOutputStream(target).use { zip ->
            writeJsonEntry(
                zip,
                "manifest.json",
                JsonLines.json.encodeToString(
                    HlzManifest.serializer(),
                    HlzManifest(
                        created_at_usec = exportTimeUsec,
                        app_version = appVersion,
                        record_count = totalRecords,
                        chunk_count = chunkCount,
                        time_range_usec = if (totalRecords == 0L) null else HlzTimeRange(minTs, maxTs),
                        indexes = HlzIndexes(
                            chunks = "indexes/chunks.json",
                            years = "indexes/years.json",
                            months = "indexes/months.json",
                            days = "indexes/days.json",
                        ),
                    ),
                ),
            )

            val chunkIndexes = mutableListOf<HlzChunkIndex>()
            var chunkId = 0L
            var buffer = ByteArrayOutputStream()
            var bufferedCount = 0L
            var bufferMin = Long.MAX_VALUE
            var bufferMax = Long.MIN_VALUE

            fun flushChunk() {
                if (bufferedCount == 0L) return
                chunkId++
                val bytes = buffer.toByteArray()
                val path = "chunks/%08d.jsonl".format(chunkId)
                zip.putNextEntry(ZipEntry(path))
                zip.write(bytes)
                zip.closeEntry()
                chunkIndexes += HlzChunkIndex(
                    id = chunkId,
                    path = path,
                    record_count = bufferedCount,
                    min_ts = bufferMin,
                    max_ts = bufferMax,
                    sha256 = Sha256.of(bytes),
                )
                buffer = ByteArrayOutputStream()
                bufferedCount = 0
                bufferMin = Long.MAX_VALUE
                bufferMax = Long.MIN_VALUE
            }

            forEachBatch { batch ->
                batch.forEach { record ->
                    val line = JsonLines.recordToLine(record).toByteArray(Charsets.UTF_8)
                    buffer.write(line)
                    buffer.write('\n'.code)
                    bufferedCount++
                    bufferMin = minOf(bufferMin, record.visitedAtUsec)
                    bufferMax = maxOf(bufferMax, record.visitedAtUsec)
                    if (bufferedCount >= CHUNK_TARGET_RECORDS) flushChunk()
                }
            }
            flushChunk()

            writeJsonEntry(
                zip,
                "indexes/chunks.json",
                JsonLines.json.encodeToString(ListSerializer(HlzChunkIndex.serializer()), chunkIndexes),
            )
            writeJsonEntry(zip, "indexes/days.json", JsonLines.json.encodeToString(JsonArray.serializer(), dayBuckets(dayCounts)))
            writeJsonEntry(zip, "indexes/months.json", JsonLines.json.encodeToString(JsonArray.serializer(), monthBuckets(dayCounts)))
            writeJsonEntry(zip, "indexes/years.json", JsonLines.json.encodeToString(JsonArray.serializer(), yearBuckets(dayCounts)))
        }
        return totalRecords
    }

    private fun dayKey(usec: Long): String {
        val seconds = Math.floorDiv(usec, 1_000_000L)
        val micros = (usec % 1_000_000L).toInt()
        val date = Instant.ofEpochSecond(seconds, micros * 1000L).atZone(ZoneOffset.UTC).toLocalDate()
        return "%04d-%02d-%02d".format(date.year, date.monthValue, date.dayOfMonth)
    }

    private fun writeJsonEntry(zip: ZipOutputStream, name: String, content: String) {
        zip.putNextEntry(ZipEntry(name))
        zip.write(content.toByteArray(Charsets.UTF_8))
        zip.closeEntry()
    }

    private fun dayBuckets(days: Map<String, Long>): JsonArray = buildJsonArray {
        days.forEach { (day, count) ->
            add(buildJsonObject { put("day", day); put("record_count", count) })
        }
    }

    private fun monthBuckets(days: Map<String, Long>): JsonArray = buildJsonArray {
        days.keys.groupBy { it.substring(0, 7) }
            .toSortedMap()
            .forEach { (month, dayKeys) ->
                add(
                    buildJsonObject {
                        put("month", month)
                        put("record_count", dayKeys.sumOf { days[it] ?: 0L })
                    },
                )
            }
    }

    private fun yearBuckets(days: Map<String, Long>): JsonArray = buildJsonArray {
        days.keys.groupBy { it.substring(0, 4) }
            .toSortedMap()
            .forEach { (year, dayKeys) ->
                add(
                    buildJsonObject {
                        put("year", year.toInt())
                        put("record_count", dayKeys.sumOf { days[it] ?: 0L })
                    },
                )
            }
    }

    companion object {
        private const val CHUNK_TARGET_RECORDS = 50_000
    }
}
