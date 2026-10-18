package com.sjasonp.historylib.core.model

data class SummarySnapshot(
    val totalRecords: Long,
    val averagePerDay: Double,
    val averagePerMonth: Double,
    val averagePerYear: Double,
    val earliestVisitUsec: Long?,
    val latestVisitUsec: Long?,
    val generatedAtUsec: Long,
    val topSites: List<TopSite>,
)

data class TopSite(
    val host: String,
    val count: Long,
)
