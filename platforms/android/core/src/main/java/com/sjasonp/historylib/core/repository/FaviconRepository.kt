package com.sjasonp.historylib.core.repository

interface FaviconRepository {
    suspend fun favicon(host: String): ByteArray?

    suspend fun clear(): Unit

    suspend fun cacheUsageBytes(): Long

    suspend fun storageUsage(): StorageUsage
}

data class StorageUsage(
    val clearableBytes: Long,
    val nonClearableBytes: Long,
)
