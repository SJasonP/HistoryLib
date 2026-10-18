package com.sjasonp.historylib

import android.app.Application
import com.sjasonp.historylib.di.AppDependencies

class HistoryLibApplication : Application() {
    val dependencies: AppDependencies by lazy { AppDependencies(this) }
}
