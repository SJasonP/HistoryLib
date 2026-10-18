package com.sjasonp.historylib.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sjasonp.historylib.core.model.DayCount
import com.sjasonp.historylib.core.model.HistoryQuery
import com.sjasonp.historylib.core.model.HistoryRecord
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.settings.AppSettings
import com.sjasonp.historylib.core.settings.AppSettingsRepository
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class PagedRecords(
    val records: List<HistoryRecord> = emptyList(),
    val loading: Boolean = false,
    val endReached: Boolean = false,
)

@OptIn(FlowPreview::class)
class LibraryViewModel(
    private val repository: HistoryRepository,
    private val settingsRepository: AppSettingsRepository,
) : ViewModel() {
    private val query = MutableStateFlow("")
    private val _search = MutableStateFlow(PagedRecords())
    val search: StateFlow<PagedRecords> = _search

    private val _dayPages = MutableStateFlow<Map<String, PagedRecords>>(emptyMap())
    val dayPages: StateFlow<Map<String, PagedRecords>> = _dayPages

    val directoryCounts: StateFlow<List<DayCount>> = repository.observeDirectoryCounts()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val settings: StateFlow<AppSettings> = settingsRepository.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AppSettings())

    init {
        viewModelScope.launch {
            query.debounce(250).distinctUntilChanged().collectLatest { text ->
                _search.value = PagedRecords()
                if (text.isNotBlank()) loadSearchPage(text, reset = true)
            }
        }
    }

    fun setQuery(text: String) {
        query.value = text.trim()
        if (text.isBlank()) _search.value = PagedRecords()
    }

    fun loadMoreSearch() {
        val text = query.value
        if (text.isNotBlank()) viewModelScope.launch { loadSearchPage(text, reset = false) }
    }

    fun loadDay(year: Int, month: Int, day: Int) {
        val key = dayKey(year, month, day)
        val current = _dayPages.value[key]
        if (current?.loading == true || current?.endReached == true) return
        viewModelScope.launch {
            _dayPages.value = _dayPages.value + (key to (current ?: PagedRecords()).copy(loading = true))
            val zone = ZoneId.systemDefault()
            val start = LocalDate.of(year, month, day).atStartOfDay(zone).toInstant()
            val end = LocalDate.of(year, month, day).plusDays(1).atStartOfDay(zone).toInstant()
            val existing = current?.records.orEmpty()
            val page = repository.loadHistoryPage(
                HistoryQuery(
                    startUsecInclusive = start.epochSecond * 1_000_000L + start.nano / 1_000L,
                    endUsecExclusive = end.epochSecond * 1_000_000L + end.nano / 1_000L,
                ),
                offset = existing.size,
                limit = PAGE_SIZE,
            )
            _dayPages.value = _dayPages.value + (
                key to PagedRecords(existing + page, loading = false, endReached = page.size < PAGE_SIZE)
            )
        }
    }

    fun updateSettings(transform: (AppSettings) -> AppSettings) {
        viewModelScope.launch { settingsRepository.update(transform) }
    }

    fun deleteRecords(uniqueKeys: Set<String>) {
        viewModelScope.launch {
            repository.delete(uniqueKeys)
            _search.value = _search.value.copy(records = _search.value.records.filterNot { it.uniqueKey in uniqueKeys })
            _dayPages.value = _dayPages.value.mapValues { (_, page) ->
                page.copy(records = page.records.filterNot { it.uniqueKey in uniqueKeys })
            }
        }
    }

    private suspend fun loadSearchPage(text: String, reset: Boolean) {
        val current = if (reset) PagedRecords() else _search.value
        if (current.loading || current.endReached) return
        _search.value = current.copy(loading = true)
        val page = repository.loadHistoryPage(
            HistoryQuery(searchText = text),
            offset = current.records.size,
            limit = PAGE_SIZE,
        )
        if (query.value != text) return
        _search.value = PagedRecords(
            records = current.records + page,
            loading = false,
            endReached = page.size < PAGE_SIZE,
        )
    }

    companion object {
        private const val PAGE_SIZE = 200

        fun dayKey(year: Int, month: Int, day: Int): String = "%04d-%02d-%02d".format(year, month, day)
    }
}
