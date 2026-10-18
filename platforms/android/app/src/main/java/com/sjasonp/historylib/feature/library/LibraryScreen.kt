package com.sjasonp.historylib.feature.library

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sjasonp.historylib.R
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.repository.FaviconRepository
import com.sjasonp.historylib.core.settings.ExpandLevel
import com.sjasonp.historylib.feature.LibraryViewModel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.text.NumberFormat
import java.util.Locale

@Composable
fun LibraryScreen(viewModel: LibraryViewModel, faviconRepository: FaviconRepository) {
    val directoryCounts by viewModel.directoryCounts.collectAsStateWithLifecycle()
    val search by viewModel.search.collectAsStateWithLifecycle()
    val dayPages by viewModel.dayPages.collectAsStateWithLifecycle()
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(
            value = query,
            onValueChange = {
                query = it
                viewModel.setQuery(it)
            },
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            placeholder = { Text(stringResource(R.string.library_search_hint)) },
            singleLine = true,
        )
        if (query.isNotBlank()) {
            SearchResults(search, settings, viewModel, faviconRepository)
        } else if (directoryCounts.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.library_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            HistoryList(directoryCounts, dayPages, settings.defaultExpandTo, settings, viewModel, faviconRepository)
        }
    }
}

@Composable
private fun SearchResults(
    page: com.sjasonp.historylib.feature.PagedRecords,
    settings: com.sjasonp.historylib.core.settings.AppSettings,
    viewModel: LibraryViewModel,
    faviconRepository: FaviconRepository,
) {
    if (page.records.isEmpty() && page.loading) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    if (page.records.isEmpty() && page.endReached) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.library_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        return
    }
    LazyColumn(Modifier.fillMaxSize()) {
        items(page.records, key = { it.uniqueKey }) { record ->
            HistoryRow(record, settings, viewModel, faviconRepository)
        }
        if (!page.endReached) {
            item(key = "search-load-more") {
                TextButton(
                    onClick = viewModel::loadMoreSearch,
                    enabled = !page.loading,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (page.loading) CircularProgressIndicator(Modifier.size(20.dp))
                    else Text(stringResource(R.string.library_load_more))
                }
            }
        }
    }
}

@Composable
private fun HistoryList(
    counts: List<com.sjasonp.historylib.core.model.DayCount>,
    dayPages: Map<String, com.sjasonp.historylib.feature.PagedRecords>,
    defaultExpandTo: ExpandLevel,
    settings: com.sjasonp.historylib.core.settings.AppSettings,
    viewModel: LibraryViewModel,
    faviconRepository: FaviconRepository,
) {
    val todayLabel = stringResource(R.string.library_today)
    val yesterdayLabel = stringResource(R.string.library_yesterday)
    val yearGroups = remember(counts, todayLabel, yesterdayLabel) {
        buildYearGroups(counts, todayLabel, yesterdayLabel)
    }
    val expandedYears = remember { mutableStateMapOf<Int, Boolean>() }
    val expandedMonths = remember { mutableStateMapOf<String, Boolean>() }
    val expandedDays = remember { mutableStateMapOf<String, Boolean>() }

    LaunchedEffect(yearGroups, defaultExpandTo) {
        applyDefaultExpansion(defaultExpandTo, yearGroups, expandedYears, expandedMonths, expandedDays)
    }

    LazyColumn(Modifier.fillMaxSize()) {
        yearGroups.forEach { yearGroup ->
            item(key = "year-${yearGroup.year}") {
                HierarchyRow(
                    title = yearGroup.title,
                    count = yearGroup.totalCount,
                    level = 0,
                    expanded = expandedYears[yearGroup.year] ?: false,
                    onClick = { toggleYear(yearGroup, expandedYears, expandedMonths, expandedDays) },
                )
            }

            if (expandedYears[yearGroup.year] == true) {
                yearGroup.monthGroups.forEach { monthGroup ->
                    item(key = "month-${monthGroup.key}") {
                        HierarchyRow(
                            title = monthGroup.title,
                            count = monthGroup.totalCount,
                            level = 1,
                            expanded = expandedMonths[monthGroup.key] ?: false,
                            onClick = { toggleMonth(monthGroup, expandedMonths, expandedDays) },
                        )
                    }

                    if (expandedMonths[monthGroup.key] == true) {
                        monthGroup.dayGroups.forEach { dayGroup ->
                            item(key = "day-${dayGroup.key}") {
                                HierarchyRow(
                                    title = dayGroup.title,
                                    count = dayGroup.count,
                                    level = 2,
                                    expanded = expandedDays[dayGroup.key] ?: false,
                                    onClick = {
                                        val expanding = !(expandedDays[dayGroup.key] ?: false)
                                        expandedDays[dayGroup.key] = expanding
                                        if (expanding) viewModel.loadDay(dayGroup.year, dayGroup.month, dayGroup.day)
                                    },
                                )
                            }

                            if (expandedDays[dayGroup.key] == true) {
                                val page = dayPages[dayGroup.key]
                                items(page?.records.orEmpty(), key = { it.uniqueKey }) { record ->
                                    HistoryRow(
                                        record = record,
                                        settings = settings,
                                        viewModel = viewModel,
                                        faviconRepository = faviconRepository,
                                        modifier = Modifier.padding(start = 48.dp),
                                    )
                                }
                                if (page?.endReached != true) {
                                    item(key = "load-${dayGroup.key}") {
                                        TextButton(
                                            onClick = { viewModel.loadDay(dayGroup.year, dayGroup.month, dayGroup.day) },
                                            enabled = page?.loading != true,
                                            modifier = Modifier.padding(start = 48.dp),
                                        ) {
                                            if (page?.loading == true) CircularProgressIndicator(Modifier.size(20.dp))
                                            else Text(stringResource(R.string.library_load_more))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private data class HistoryDayGroup(
    val key: String,
    val title: String,
    val year: Int,
    val month: Int,
    val day: Int,
    val count: Long,
)

private data class HistoryMonthGroup(
    val key: String,
    val title: String,
    val dayGroups: List<HistoryDayGroup>,
) {
    val totalCount: Long get() = dayGroups.sumOf { it.count }
}

private data class HistoryYearGroup(
    val year: Int,
    val title: String,
    val monthGroups: List<HistoryMonthGroup>,
) {
    val totalCount: Long get() = monthGroups.sumOf { it.totalCount }
}

private fun buildYearGroups(
    counts: List<com.sjasonp.historylib.core.model.DayCount>,
    todayLabel: String,
    yesterdayLabel: String,
): List<HistoryYearGroup> {
    val zone = ZoneId.systemDefault()
    val dayGroups = counts.map { count ->
        val date = LocalDate.of(count.year, count.month, count.day)
        HistoryDayGroup(
            key = LibraryViewModel.dayKey(count.year, count.month, count.day),
            title = dayTitle(date, zone, todayLabel, yesterdayLabel),
            year = count.year,
            month = count.month,
            day = count.day,
            count = count.recordCount,
        )
    }

    val monthGroups = dayGroups
        .groupBy { it.key.substringBeforeLast("-") }
        .map { (key, days) ->
            val parts = key.split("-")
            val monthDate = LocalDate.of(parts[0].toInt(), parts[1].toInt(), 1)
            HistoryMonthGroup(
                key = key,
                title = DateTimeFormatter.ofPattern("yyyy MMMM", Locale.getDefault()).format(monthDate),
                dayGroups = days.sortedByDescending { it.key },
            )
        }
        .sortedByDescending { it.key }

    return monthGroups
        .groupBy { it.key.substringBefore("-").toInt() }
        .map { (year, months) ->
            HistoryYearGroup(
                year = year,
                title = year.toString(),
                monthGroups = months.sortedByDescending { it.key },
            )
        }
        .sortedByDescending { it.year }
}

private fun applyDefaultExpansion(
    level: ExpandLevel,
    yearGroups: List<HistoryYearGroup>,
    years: MutableMap<Int, Boolean>,
    months: MutableMap<String, Boolean>,
    days: MutableMap<String, Boolean>,
) {
    years.clear()
    months.clear()
    days.clear()
    when (level) {
        ExpandLevel.NONE -> Unit
        ExpandLevel.YEAR -> yearGroups.forEach { years[it.year] = true }
        ExpandLevel.MONTH -> yearGroups.forEach { yearGroup ->
            years[yearGroup.year] = true
            yearGroup.monthGroups.forEach { months[it.key] = true }
        }
        ExpandLevel.DAY -> yearGroups.forEach { yearGroup ->
            years[yearGroup.year] = true
            yearGroup.monthGroups.forEach { monthGroup ->
                months[monthGroup.key] = true
                monthGroup.dayGroups.forEach { days[it.key] = true }
            }
        }
    }
}

private fun toggleYear(
    yearGroup: HistoryYearGroup,
    years: MutableMap<Int, Boolean>,
    months: MutableMap<String, Boolean>,
    days: MutableMap<String, Boolean>,
) {
    if (years[yearGroup.year] == true) {
        years.remove(yearGroup.year)
        yearGroup.monthGroups.forEach { monthGroup ->
            months.remove(monthGroup.key)
            monthGroup.dayGroups.forEach { days.remove(it.key) }
        }
    } else {
        years[yearGroup.year] = true
    }
}

private fun toggleMonth(
    monthGroup: HistoryMonthGroup,
    months: MutableMap<String, Boolean>,
    days: MutableMap<String, Boolean>,
) {
    if (months[monthGroup.key] == true) {
        months.remove(monthGroup.key)
        monthGroup.dayGroups.forEach { days.remove(it.key) }
    } else {
        months[monthGroup.key] = true
    }
}

@Composable
private fun HierarchyRow(
    title: String,
    count: Long,
    level: Int,
    expanded: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(start = (16 + level * 16).dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (expanded) "▾" else "▸", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = title,
                modifier = Modifier.padding(start = 8.dp),
                style = if (level == 0) MaterialTheme.typography.titleMedium else MaterialTheme.typography.titleSmall,
            )
        }
        Text(NumberFormat.getIntegerInstance().format(count), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun dayTitle(date: LocalDate, zone: ZoneId, todayLabel: String, yesterdayLabel: String): String {
    val today = LocalDate.now(zone)
    return when (date) {
        today -> todayLabel
        today.minusDays(1) -> yesterdayLabel
        else -> DateTimeFormatter.ofPattern("yyyy-MM-dd EEEE", Locale.getDefault()).format(date)
    }
}

@Composable
private fun HistoryRow(
    record: HistoryRecord,
    settings: com.sjasonp.historylib.core.settings.AppSettings,
    viewModel: LibraryViewModel,
    faviconRepository: FaviconRepository,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Row(
        modifier = Modifier
            .then(modifier)
            .fillMaxWidth()
            .clickable(enabled = settings.openLinkOnTap) {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(record.url))
                context.startActivity(intent)
            }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (settings.showSiteIcons) {
            FaviconImage(host = hostOf(record.url), repository = faviconRepository)
        }
        Column(Modifier.weight(1f).padding(start = if (settings.showSiteIcons) 10.dp else 0.dp)) {
            Text(record.title.ifBlank { record.url }, style = MaterialTheme.typography.bodyLarge, maxLines = 1)
            Text(record.url, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            if (settings.showVisitTime) {
                Text(
                    formatInstant(record.visitedAtUsec),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        if (settings.enableDeletion) {
            TextButton(onClick = { viewModel.deleteRecords(setOf(record.uniqueKey)) }) {
                Text(stringResource(R.string.library_delete))
            }
        }
    }
}

@Composable
private fun FaviconImage(host: String, repository: FaviconRepository) {
    val bytes by produceState<ByteArray?>(initialValue = null, host) {
        value = repository.favicon(host)
    }
    if (bytes != null) {
        val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes!!.size) }
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

private fun hostOf(url: String): String {
    return try {
        java.net.URI(url).host ?: ""
    } catch (_: Exception) {
        ""
    }
}

private fun formatInstant(usec: Long): String {
    val seconds = Math.floorDiv(usec, 1_000_000L)
    val micros = (usec % 1_000_000L).toInt()
    return DateTimeFormatter.ofLocalizedTime(FormatStyle.MEDIUM)
        .withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochSecond(seconds, micros * 1000L))
}
