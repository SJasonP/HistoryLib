package com.sjasonp.historylib.feature

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sjasonp.historylib.core.model.SummarySnapshot
import com.sjasonp.historylib.core.repository.HistoryRepository
import com.sjasonp.historylib.core.summary.SummaryCalculator
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

class SummaryViewModel(repository: HistoryRepository) : ViewModel() {
    val summary: StateFlow<SummarySnapshot> = repository.observeSummary()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SummaryCalculator.empty(0L))
}
