package com.sjasonp.historylib.feature.summary

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.sjasonp.historylib.R
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.feature.SummaryViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.text.NumberFormat

@Composable
fun SummaryScreen(viewModel: SummaryViewModel) {
    val summary by viewModel.summary.collectAsStateWithLifecycle()
    if (summary.totalRecords == 0L) {
        EmptySummary()
        return
    }
    SummaryContent(summary)
}

@Composable
private fun SummaryContent(summary: SummarySnapshot) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            StatCard(stringResource(R.string.summary_total_records), formatInteger(summary.totalRecords))
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard(stringResource(R.string.summary_avg_day), twoDecimals(summary.averagePerDay), Modifier.weight(1f))
                StatCard(stringResource(R.string.summary_avg_month), twoDecimals(summary.averagePerMonth), Modifier.weight(1f))
                StatCard(stringResource(R.string.summary_avg_year), twoDecimals(summary.averagePerYear), Modifier.weight(1f))
            }
        }
        item {
            Text(
                stringResource(R.string.summary_top_sites),
                style = MaterialTheme.typography.titleMedium,
            )
        }
        items(summary.topSites) { site ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(site.host, style = MaterialTheme.typography.bodyLarge)
                Text(formatInteger(site.count), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            Text(
                text = stringResource(R.string.summary_last_modified, formatInstant(summary.generatedAtUsec)),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp)) {
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge)
            Text(value, style = MaterialTheme.typography.headlineSmall)
        }
    }
}

@Composable
private fun EmptySummary() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = stringResource(R.string.summary_empty),
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

private fun twoDecimals(value: Double): String = "%.2f".format(value)

private fun formatInteger(value: Long): String = NumberFormat.getIntegerInstance().format(value)

private fun formatInstant(usec: Long): String {
    if (usec <= 0) return "-"
    val seconds = Math.floorDiv(usec, 1_000_000L)
    val micros = (usec % 1_000_000L).toInt()
    return DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)
        .withZone(ZoneId.systemDefault())
        .format(Instant.ofEpochSecond(seconds, micros * 1000L))
}
