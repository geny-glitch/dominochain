package com.bg

import android.content.Context
import java.time.LocalDate

enum class TrackerType(
    val id: String,
    val title: String,
    val unitLabel: String
) {
    Cigarettes("cigarettes", "Cigarettes fumées", "cigarettes")
}

data class TrackerSnapshot(
    val type: TrackerType,
    val count: Int,
    val date: LocalDate = LocalDate.now()
)

class TrackerRepository(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun trackers(): List<TrackerSnapshot> {
        return TrackerType.entries.map { snapshot(it) }
    }

    fun snapshot(type: TrackerType): TrackerSnapshot {
        val today = LocalDate.now()
        return TrackerSnapshot(type, count(type, today), today)
    }

    fun dailySnapshots(type: TrackerType, days: Int = DEFAULT_HISTORY_DAYS): List<TrackerSnapshot> {
        val today = LocalDate.now()
        return (0 until days).map { offset ->
            val date = today.minusDays(offset.toLong())
            TrackerSnapshot(type, count(type, date), date)
        }
    }

    fun increment(type: TrackerType): TrackerSnapshot {
        val today = LocalDate.now()
        val updated = count(type, today) + 1
        prefs.edit()
            .putInt(dailyCountKey(type, today), updated)
            .putInt(countKey(type), prefs.getInt(countKey(type), 0) + 1)
            .apply()
        return TrackerSnapshot(type, updated, today)
    }

    private fun count(type: TrackerType, date: LocalDate): Int {
        return prefs.getInt(dailyCountKey(type, date), 0)
    }

    private fun countKey(type: TrackerType): String = "tracker_${type.id}_count"

    private fun dailyCountKey(type: TrackerType, date: LocalDate): String {
        return "tracker_${type.id}_${date}_count"
    }

    companion object {
        private const val PREFS_NAME = "trackers"
        private const val DEFAULT_HISTORY_DAYS = 14
    }
}
