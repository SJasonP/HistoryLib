package com.sjasonp.historylib.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        HistoryRecordEntity::class,
        DirectoryCountEntity::class,
        SummarySnapshotEntity::class,
        ImportRunEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class HistoryLibDatabase : RoomDatabase() {
    abstract fun historyDao(): HistoryDao

    companion object {
        fun build(context: Context): HistoryLibDatabase {
            return Room.databaseBuilder(
                context.applicationContext,
                HistoryLibDatabase::class.java,
                "historylib.db",
            ).build()
        }
    }
}
