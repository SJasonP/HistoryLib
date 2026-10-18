package com.sjasonp.historylib.core.dedup

import org.junit.Assert.assertEquals
import org.junit.Test

class DedupTest {
    @Test
    fun normalizesDefaultPortsFragmentAndTrailingSlash() {
        assertEquals(
            "https://example.com/a?q=1",
            UrlNormalizer.normalize("HTTPS://Example.com:443/a/?q=1#frag"),
        )
    }

    @Test
    fun signatureFloorsToSeconds() {
        val signature = DedupSignature.from("https://example.com/", 1_725_000_000_999_999L, " Safari ")
        assertEquals("https://example.com/", signature.normalizedUrl)
        assertEquals(1_725_000_000L, signature.visitedSecond)
        assertEquals("safari", signature.normalizedBrowser)
    }

    @Test
    fun toleranceBuildsInclusiveRange() {
        val signature = DedupSignature("https://example.com/", 10, "chrome")
        assertEquals(setOf("https://example.com/|9|chrome", "https://example.com/|10|chrome", "https://example.com/|11|chrome"), signature.matchingKeys(1))
    }
}
