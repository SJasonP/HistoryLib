package com.sjasonp.historylib

import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.sjasonp.historylib.di.AppDependencies
import com.sjasonp.historylib.feature.LibraryViewModel
import com.sjasonp.historylib.feature.ManageViewModel
import com.sjasonp.historylib.feature.SummaryViewModel
import com.sjasonp.historylib.feature.library.LibraryScreen
import com.sjasonp.historylib.feature.manage.ManageScreen
import com.sjasonp.historylib.feature.summary.SummaryScreen
import com.sjasonp.historylib.ui.theme.HistoryLibTheme
import java.time.ZoneId

@Composable
fun HistoryLibApp() {
    val context = LocalContext.current
    val dependencies = (context.applicationContext as HistoryLibApplication).dependencies

    LaunchedEffect(Unit) {
        val now = System.currentTimeMillis() * 1000L
        dependencies.historyRepository.cancelInterruptedImportRuns(now)
        dependencies.historyRepository.regenerateSummary(now)
        dependencies.historyRepository.regenerateDirectoryCounts(ZoneId.systemDefault().id)
    }

    HistoryLibTheme {
        var destinationName by rememberSaveable { mutableStateOf(AppDestination.SUMMARY.name) }
        val currentDestination = AppDestination.valueOf(destinationName)

        NavigationSuiteScaffold(
            navigationSuiteItems = {
                AppDestination.entries.forEach { destination ->
                    item(
                        selected = destination == currentDestination,
                        onClick = { destinationName = destination.name },
                        icon = { Text(destination.symbol) },
                        label = { Text(stringResource(destination.labelRes)) },
                    )
                }
            },
        ) {
            when (currentDestination) {
                AppDestination.SUMMARY -> SummaryRoute(dependencies)
                AppDestination.LIBRARY -> LibraryRoute(dependencies)
                AppDestination.MANAGE -> ManageRoute(dependencies)
            }
        }
    }
}

@Composable
private fun SummaryRoute(dependencies: AppDependencies) {
    val viewModel: SummaryViewModel = viewModel(
        factory = viewModelFactory {
            initializer { SummaryViewModel(dependencies.historyRepository) }
        },
    )
    SummaryScreen(viewModel)
}

@Composable
private fun LibraryRoute(dependencies: AppDependencies) {
    val viewModel: LibraryViewModel = viewModel(
        factory = viewModelFactory {
            initializer {
                LibraryViewModel(dependencies.historyRepository, dependencies.appSettingsRepository)
            }
        },
    )
    LibraryScreen(viewModel, dependencies.faviconRepository)
}

@Composable
private fun ManageRoute(dependencies: AppDependencies) {
    val viewModel: ManageViewModel = viewModel(
        factory = viewModelFactory { initializer { ManageViewModel(dependencies) } },
    )
    ManageScreen(viewModel)
}
