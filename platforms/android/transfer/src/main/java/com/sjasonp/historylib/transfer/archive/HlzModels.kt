package com.sjasonp.historylib.transfer.archive

import kotlinx.serialization.Serializable

@Serializable
data class HlzManifest(
    val format: String = "historylib",
    val format_version: Int = 1,
    val created_at_usec: Long,
    val app_name: String = "HistoryLib",
    val app_version: String,
    val record_schema: String = "hl_record_v1",
    val record_count: Long,
    val chunk_count: Long,
    val time_range_usec: HlzTimeRange? = null,
    val chunk_encoding: String = "jsonl",
    val chunk_target_records: Int = 50_000,
    val feature_flags: List<String> = emptyList(),
    val indexes: HlzIndexes,
    val summary: String? = null,
)

@Serializable
data class HlzTimeRange(
    val min: Long,
    val max: Long,
)

@Serializable
data class HlzIndexes(
    val chunks: String,
    val years: String? = null,
    val months: String? = null,
    val days: String? = null,
)

@Serializable
data class HlzChunkIndex(
    val id: Long,
    val path: String,
    val record_count: Long,
    val min_ts: Long,
    val max_ts: Long,
    val sha256: String,
)
