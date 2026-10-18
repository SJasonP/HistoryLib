package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.core.dedup.DedupSignature
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.transfer.archive.JsonLines
import com.sjasonp.historylib.transfer.archive.StreamingJson
import com.sjasonp.historylib.transfer.json.FlexibleJson
import kotlinx.serialization.json.JsonObject
import java.io.InputStream

class SafariImporter {
    fun parse(input: InputStream, sourceFileName: String, importTimeUsec: Long): Sequence<HistoryRecord?> {
        return readObjects(input, "history").map { obj ->
            recordFromObject(obj, sourceFileName, importTimeUsec)
        }
    }

    private fun readObjects(input: InputStream, arrayKey: String): Sequence<JsonObject> = sequence {
        val stream = StreamingJson(input.bufferedReader(Charsets.UTF_8))
        if (!stream.skipToArray(arrayKey)) return@sequence
        while (true) {
            val text = stream.nextObjectText() ?: break
            yield(JsonLines.json.parseToJsonElement(text) as JsonObject)
        }
    }

    private fun recordFromObject(obj: JsonObject, sourceFileName: String, importTimeUsec: Long): HistoryRecord? {
        val url = FlexibleJson.recordString(obj, "url")?.takeIf { it.isNotBlank() } ?: return null
        val visitedAt = FlexibleJson.longOrNull(obj["time_usec"]) ?: return null
        val browser = "Safari"
        val uniqueKey = DedupSignature.from(url, visitedAt, browser).canonicalKey()
        return HistoryRecord(
            uniqueKey = uniqueKey,
            url = url,
            title = FlexibleJson.recordString(obj, "title").orEmpty(),
            visitedAtUsec = visitedAt,
            visitCount = (FlexibleJson.intOrNull(obj["visit_count"]) ?: 1).coerceAtLeast(1),
            sourceBrowser = browser,
            sourceFileName = sourceFileName,
            rawTimeUsec = visitedAt,
            sourceUrl = FlexibleJson.recordString(obj, "source_url"),
            sourceTimeUsec = FlexibleJson.longOrNull(obj["source_time_usec"]),
            destinationUrl = FlexibleJson.recordString(obj, "destination_url"),
            destinationTimeUsec = FlexibleJson.longOrNull(obj["destination_time_usec"]),
            latestVisitWasHttpGet = FlexibleJson.booleanOrNull(obj["latest_visit_was_http_get"]),
            importedAtUsec = importTimeUsec,
        )
    }
}
