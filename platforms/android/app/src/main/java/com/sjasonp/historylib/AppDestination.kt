package com.sjasonp.historylib

import androidx.annotation.StringRes

enum class AppDestination(
    @param:StringRes val labelRes: Int,
    val symbol: String,
) {
    SUMMARY(R.string.destination_summary, "◷"),
    LIBRARY(R.string.destination_library, "▤"),
    MANAGE(R.string.destination_manage, "⚙"),
}
