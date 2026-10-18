package com.sjasonp.historylib.transfer.archive

import com.sjasonp.historylib.core.dedup.DedupSignature
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.json.FlexibleJson
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.InputStreamReader

object JsonLines {
    val json = Json { ignoreUnknownKeys = true }

    fun recordToLine(record: HistoryRecord): String {
        val obj = buildJsonObject {
            put("u", record.url)
            put("ts", record.visitedAtUsec)
            put("t", record.title)
            put("vc", record.visitCount)
            put("uk", record.uniqueKey)
            put("sb", record.sourceBrowser)
            put("ia", record.importedAtUsec)
            if (record.rawTimeUsec != 0L) put("rt", record.rawTimeUsec)
            if (record.sourceFileName.isNotBlank()) put("sf", record.sourceFileName)
            record.sourceUrl?.let { put("su", it) }
            record.sourceTimeUsec?.let { put("st", it) }
            record.destinationUrl?.let { put("du", it) }
            record.destinationTimeUsec?.let { put("dt", it) }
            record.latestVisitWasHttpGet?.let { put("hg", it) }
        }
        return json.encodeToString(JsonObject.serializer(), obj)
    }

    fun recordFromObject(obj: JsonObject, defaultBrowser: String, importTimeUsec: Long): HistoryRecord? {
        val url = FlexibleJson.recordString(obj, "u")?.takeIf { it.isNotBlank() } ?: return null
        val ts = FlexibleJson.longOrNull(obj["ts"]) ?: return null
        val browser = FlexibleJson.recordString(obj, "sb")?.takeIf { it.isNotBlank() } ?: defaultBrowser
        val uniqueKey = FlexibleJson.recordString(obj, "uk")?.takeIf { it.isNotBlank() }
            ?: DedupSignature.from(url, ts, browser).canonicalKey()
        return HistoryRecord(
            uniqueKey = uniqueKey,
            url = url,
            title = FlexibleJson.recordString(obj, "t").orEmpty(),
            visitedAtUsec = ts,
            visitCount = (FlexibleJson.intOrNull(obj["vc"]) ?: 1).coerceAtLeast(1),
            sourceBrowser = browser,
            sourceFileName = FlexibleJson.recordString(obj, "sf").orEmpty(),
            rawTimeUsec = FlexibleJson.longOrNull(obj["rt"]) ?: 0L,
            sourceUrl = FlexibleJson.recordString(obj, "su"),
            sourceTimeUsec = FlexibleJson.longOrNull(obj["st"]),
            destinationUrl = FlexibleJson.recordString(obj, "du"),
            destinationTimeUsec = FlexibleJson.longOrNull(obj["dt"]),
            latestVisitWasHttpGet = FlexibleJson.booleanOrNull(obj["hg"]),
            importedAtUsec = FlexibleJson.longOrNull(obj["ia"]) ?: importTimeUsec,
        )
    }

    fun readLines(input: InputStream): Sequence<String> {
        return BufferedReader(InputStreamReader(input, Charsets.UTF_8)).lineSequence()
    }

    fun readBoundedLines(input: InputStream, maxLineBytes: Int = ZipSafe.MAX_RECORD_BYTES): Sequence<String> = sequence {
        val line = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read == -1) break
            for (index in 0 until read) {
                val byte = buffer[index]
                if (byte == '\n'.code.toByte()) {
                    yield(line.toString(Charsets.UTF_8.name()).removeSuffix("\r"))
                    line.reset()
                } else {
                    if (line.size() >= maxLineBytes) throw ZipValidationException("JSONL record exceeds size limit")
                    line.write(byte.toInt())
                }
            }
        }
        if (line.size() > 0) yield(line.toString(Charsets.UTF_8.name()).removeSuffix("\r"))
    }
}
