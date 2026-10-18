package com.sjasonp.historylib.core.dedup

data class DedupSignature(
    val normalizedUrl: String,
    val visitedSecond: Long,
    val normalizedBrowser: String,
) {
    fun canonicalKey(): String = "$normalizedUrl|$visitedSecond|$normalizedBrowser"

    fun matchingKeys(toleranceSeconds: Int): Set<String> {
        val bounded = toleranceSeconds.coerceAtLeast(0)
        return (visitedSecond - bounded..visitedSecond + bounded)
            .map { second -> "$normalizedUrl|$second|$normalizedBrowser" }
            .toSet()
    }

    companion object {
        fun from(url: String, visitedAtUsec: Long, browser: String): DedupSignature {
            return DedupSignature(
                normalizedUrl = UrlNormalizer.normalize(url),
                visitedSecond = Math.floorDiv(visitedAtUsec, 1_000_000L),
                normalizedBrowser = UrlNormalizer.normalizeBrowser(browser),
            )
        }
    }
}
