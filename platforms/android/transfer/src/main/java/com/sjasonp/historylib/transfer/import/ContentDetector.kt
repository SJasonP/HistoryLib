package com.sjasonp.historylib.transfer.import

import com.sjasonp.historylib.transfer.HistoryImportFormat
import com.sjasonp.historylib.transfer.archive.ZipSafe
import java.io.InputStream
import java.util.zip.ZipInputStream

object ContentDetector {
    private const val PREFIX_BYTES = 65_536

    fun detectJson(prefix: String): HistoryImportFormat? {
        val probe = JsonPrefixProbe(prefix)
        if (probe.hasTopLevelArray("Browser History")) return HistoryImportFormat.CHROME_TAKEOUT
        return if (
            probe.hasTopLevelArray("history") &&
            probe.objectStringValue("metadata", "browser_name")?.equals("Safari", ignoreCase = true) == true &&
            probe.objectStringValue("metadata", "data_type")?.equals("history", ignoreCase = true) == true
        ) HistoryImportFormat.SAFARI else null
    }

    fun sniffZipEntries(input: InputStream): HistoryImportFormat? {
        var detected: HistoryImportFormat? = null
        val seen = mutableSetOf<String>()
        var entryCount = 0
        ZipInputStream(input).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = ZipSafe.safeEntryName(entry.name)
                if (++entryCount > ZipSafe.MAX_ENTRY_COUNT) throw com.sjasonp.historylib.transfer.archive.ZipValidationException("Archive has too many entries")
                if (!seen.add(name)) throw com.sjasonp.historylib.transfer.archive.ZipValidationException("Duplicate ZIP entry: $name")
                if (name == "manifest.json") return HistoryImportFormat.HISTORYLIB_ARCHIVE
                if (detected == null && name.endsWith(".json", ignoreCase = true)) {
                    val bytes = zip.readNBytes(PREFIX_BYTES)
                    detected = detectJson(String(bytes, Charsets.UTF_8))
                }
                zip.closeEntry()
            }
        }
        return detected
    }
}

/** Bounded structural probe used when the full JSON document may be very large. */
private class JsonPrefixProbe(private val source: String) {
    fun hasTopLevelArray(key: String): Boolean {
        val valueStart = valueStartForKey(key, objectStart = 0, objectDepth = 1) ?: return false
        return source.getOrNull(valueStart) == '['
    }

    fun objectStringValue(objectKey: String, childKey: String): String? {
        val objectStart = valueStartForKey(objectKey, objectStart = 0, objectDepth = 1) ?: return null
        if (source.getOrNull(objectStart) != '{') return null
        val valueStart = valueStartForKey(childKey, objectStart, objectDepth = 2) ?: return null
        return parseStringAt(valueStart)?.first
    }

    private fun valueStartForKey(key: String, objectStart: Int, objectDepth: Int): Int? {
        var index = objectStart
        var depth = objectDepth - 1
        while (index < source.length) {
            when (source[index]) {
                '{', '[' -> {
                    depth++
                    index++
                }
                '}', ']' -> {
                    depth--
                    if (depth < objectDepth - 1) return null
                    index++
                }
                '"' -> {
                    val parsed = parseStringAt(index) ?: return null
                    val token = parsed.first
                    index = parsed.second
                    if (depth == objectDepth) {
                        var cursor = skipWhitespace(index)
                        if (source.getOrNull(cursor) == ':') {
                            cursor = skipWhitespace(cursor + 1)
                            if (token == key) return cursor
                        }
                    }
                }
                else -> index++
            }
        }
        return null
    }

    private fun parseStringAt(start: Int): Pair<String, Int>? {
        if (source.getOrNull(start) != '"') return null
        val value = StringBuilder()
        var index = start + 1
        var escaped = false
        while (index < source.length) {
            val char = source[index++]
            if (escaped) {
                value.append(char)
                escaped = false
            } else when (char) {
                '\\' -> escaped = true
                '"' -> return value.toString() to index
                else -> value.append(char)
            }
        }
        return null
    }

    private fun skipWhitespace(start: Int): Int {
        var index = start
        while (index < source.length && source[index].isWhitespace()) index++
        return index
    }
}
