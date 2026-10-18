package com.sjasonp.historylib.transfer

data class TransferProgress(
    val phase: TransferPhase,
    val completedUnits: Long? = null,
    val totalUnits: Long? = null,
) {
    init {
        require(completedUnits == null || completedUnits >= 0)
        require(totalUnits == null || totalUnits >= 0)
        require(completedUnits == null || totalUnits == null || completedUnits <= totalUnits)
    }

    val isDeterminate: Boolean
        get() = completedUnits != null && totalUnits != null
}

enum class TransferPhase {
    DETECTING,
    AUTHENTICATING,
    READING,
    VALIDATING,
    WRITING,
    MERGING,
    CLEANING_UP,
}
