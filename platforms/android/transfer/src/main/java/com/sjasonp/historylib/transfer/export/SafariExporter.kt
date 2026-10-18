package com.sjasonp.historylib.transfer.export

import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.HistoryExportSplit
import com.sjasonp.historylib.transfer.archive.JsonLines
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.BufferedWriter
import java.io.OutputStream
import java.io.OutputStreamWriter
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class SafariExporter {
    suspend fun exportTo(
        forEachBatch: suspend (suspend (List<HistoryRecord>) -> Unit) -> Unit,
        split: HistoryExportSplit,
        exportTimeUsec: Long,
        out: OutputStream,
    ): Long {
        var recordCount = 0L
        ZipOutputStream(out).use { zip ->
            if (split == HistoryExportSplit.SINGLE) {
                zip.putNextEntry(ZipEntry("History.json"))
                val writer = SafariJsonWriter(zip)
                writer.start(exportTimeUsec)
                forEachBatch { batch ->
                    batch.forEach { record ->
                        writer.write(record)
                        recordCount++
                    }
                }
                writer.finish()
                zip.closeEntry()
            } else {
                val buckets = sortedSetOf<String>()
                forEachBatch { batch ->
                    batch.forEach { record -> buckets += bucketKey(record, split) }
                }
                for (bucket in buckets) {
                    zip.putNextEntry(ZipEntry("History-$bucket.json"))
                    val writer = SafariJsonWriter(zip)
                    writer.start(exportTimeUsec)
                    var bucketCount = 0L
                    forEachBatch { batch ->
                        batch.forEach { record ->
                            if (bucketKey(record, split) == bucket) {
                                writer.write(record)
                                bucketCount++
                            }
                        }
                    }
                    writer.finish()
                    zip.closeEntry()
                    recordCount += bucketCount
                }
            }
        }
        return recordCount
    }

    private fun bucketKey(record: HistoryRecord, split: HistoryExportSplit): String {
        val local = record.localDateTime()
        return when (split) {
            HistoryExportSplit.BY_YEAR -> "%04d".format(local.year)
            HistoryExportSplit.BY_MONTH -> "%04d-%02d".format(local.year, local.monthValue)
            HistoryExportSplit.BY_DAY -> "%04d-%02d-%02d".format(local.year, local.monthValue, local.dayOfMonth)
            HistoryExportSplit.SINGLE -> "single"
        }
    }

    private fun HistoryRecord.localDateTime(): ZonedDateTime {
        val seconds = Math.floorDiv(visitedAtUsec, 1_000_000L)
        val micros = (visitedAtUsec % 1_000_000L).toInt()
        return Instant.ofEpochSecond(seconds, micros * 1000L).atZone(ZoneId.systemDefault())
    }

    private class SafariJsonWriter(out: OutputStream) {
        private val writer = BufferedWriter(OutputStreamWriter(out, Charsets.UTF_8))
        private var first = true

        fun start(exportTimeUsec: Long) {
            writer.write(
                "{\"metadata\":{\"browser_name\":\"Safari\",\"data_type\":\"history\"," +
                    "\"schema_version\":1,\"export_time_usec\":$exportTimeUsec},\"history\":[",
            )
        }

        fun write(record: HistoryRecord) {
            if (!first) writer.write(",")
            first = false
            writer.write(recordJson(record))
        }

        fun finish() {
            writer.write("]}")
            writer.flush()
        }
    }

    companion object {
        private fun recordJson(record: HistoryRecord): String {
            val obj = buildJsonObject {
                put("url", record.url)
                put("time_usec", record.visitedAtUsec)
                put("visit_count", record.visitCount)
                put("title", record.title)
                record.sourceUrl?.let { put("source_url", it) }
                record.sourceTimeUsec?.let { put("source_time_usec", it) }
                record.destinationUrl?.let { put("destination_url", it) }
                record.destinationTimeUsec?.let { put("destination_time_usec", it) }
                record.latestVisitWasHttpGet?.let { put("latest_visit_was_http_get", it) }
            }
            return JsonLines.json.encodeToString(JsonObject.serializer(), obj)
        }
    }
}
