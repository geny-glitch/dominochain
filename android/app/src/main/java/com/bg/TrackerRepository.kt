package com.bg

import android.content.Context

enum class TrackerType(
    val id: String,
    val title: String,
    val unitLabel: String
) {
    Cigarettes("cigarettes", "Cigarettes fumées", "cigarettes")
}

data class TrackerSnapshot(
    val type: TrackerType,
    val count: Int
)

class TrackerRepository(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun trackers(): List<TrackerSnapshot> {
        return TrackerType.entries.map { snapshot(it) }
    }

    fun snapshot(type: TrackerType): TrackerSnapshot {
        return TrackerSnapshot(type, count(type))
    }

    fun increment(type: TrackerType): TrackerSnapshot {
        val updated = count(type) + 1
        prefs.edit()
            .putInt(countKey(type), updated)
            .apply()
        return TrackerSnapshot(type, updated)
    }

    private fun count(type: TrackerType): Int {
        return prefs.getInt(countKey(type), 0)
    }

    private fun countKey(type: TrackerType): String = "tracker_${type.id}_count"

    companion object {
        private const val PREFS_NAME = "trackers"
    }
}
