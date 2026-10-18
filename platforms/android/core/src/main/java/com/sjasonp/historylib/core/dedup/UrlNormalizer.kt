package com.sjasonp.historylib.core.dedup

import java.net.URI

/**
 * Single source of truth for URL and browser normalization. Shared by every
 * importer and by post-sync duplicate cleanup; see shared/specs/deduplication.md.
 */
object UrlNormalizer {
    fun normalize(rawUrl: String): String {
        val trimmed = rawUrl.trim()
        return try {
            val uri = URI(trimmed)
            val scheme = uri.scheme?.lowercase() ?: return trimmed.lowercase()
            var host = uri.host?.lowercase() ?: return trimmed.lowercase()
            var port = uri.port
            if (scheme == "http" && port == 80) port = -1
            if (scheme == "https" && port == 443) port = -1

            val authority = if (port > 0) "$host:$port" else host
            var path = uri.rawPath.ifEmpty { "/" }
            if (path != "/" && path.endsWith("/")) {
                path = path.dropLast(1)
            }
            val query = uri.rawQuery?.let { "?$it" } ?: ""
            "$scheme://$authority$path$query"
        } catch (_: Exception) {
            trimmed.lowercase()
        }
    }

    fun normalizeBrowser(rawBrowser: String): String = rawBrowser.trim().lowercase()

    fun hostOrDefault(rawUrl: String): String {
        return try {
            URI(normalize(rawUrl)).host?.trim()?.lowercase().orEmpty().ifBlank { "(unknown)" }
        } catch (_: Exception) {
            "(unknown)"
        }
    }
}
