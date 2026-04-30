package com.bg

import android.content.Context
import com.bg.api.CigaretteEntryRequest
import com.bg.api.CigaretteTrackerResponse
import com.bg.api.RetrofitClient
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
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

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
        storeDailyCount(type, today, updated)
        return TrackerSnapshot(type, updated, today)
    }

    suspend fun refreshRemote(type: TrackerType = TrackerType.Cigarettes): Result<TrackerSnapshot> {
        val sessionManager = SessionManager(appContext)
        if (!sessionManager.isLoggedIn) {
            return Result.success(snapshot(type))
        }

        return try {
            RetrofitClient.sessionManager = sessionManager
            val response = RetrofitClient.api.getCigarettes()
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.failure(Exception("Empty response"))
                Result.success(applyRemote(type, body))
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun incrementRemote(type: TrackerType = TrackerType.Cigarettes): Result<TrackerSnapshot> {
        val sessionManager = SessionManager(appContext)
        if (!sessionManager.isLoggedIn) {
            return Result.failure(Exception("Not logged in"))
        }

        return try {
            RetrofitClient.sessionManager = sessionManager
            val response = RetrofitClient.api.createCigaretteEntry(CigaretteEntryRequest(count = 1))
            if (response.isSuccessful) {
                val body = response.body() ?: return Result.failure(Exception("Empty response"))
                Result.success(applyRemote(type, body))
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private fun applyRemote(type: TrackerType, response: CigaretteTrackerResponse): TrackerSnapshot {
        prefs.edit().apply {
            response.history.forEach { row ->
                runCatching { LocalDate.parse(row.date) }.getOrNull()?.let { date ->
                    putInt(dailyCountKey(type, date), row.count)
                    putInt(dailyChasterSecondsKey(type, date), row.chaster_seconds ?: 0)
                }
            }
            apply()
        }

        val todayRow = response.today
        val today = todayRow?.date
            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?: LocalDate.now()
        val count = todayRow?.count ?: response.today_count ?: count(type, today)
        prefs.edit().putInt(dailyCountKey(type, today), count).apply()
        return TrackerSnapshot(type, count, today)
    }

    private fun count(type: TrackerType, date: LocalDate): Int {
        return prefs.getInt(dailyCountKey(type, date), 0)
    }

    fun chasterSeconds(type: TrackerType, date: LocalDate): Int {
        return prefs.getInt(dailyChasterSecondsKey(type, date), 0)
    }

    private fun storeDailyCount(type: TrackerType, date: LocalDate, count: Int) {
        prefs.edit().putInt(dailyCountKey(type, date), count).apply()
    }

    private fun dailyCountKey(type: TrackerType, date: LocalDate): String {
        return "tracker_${type.id}_${date}_count"
    }

    private fun dailyChasterSecondsKey(type: TrackerType, date: LocalDate): String {
        return "tracker_${type.id}_${date}_chaster_seconds"
    }

    companion object {
        private const val PREFS_NAME = "trackers"
        private const val DEFAULT_HISTORY_DAYS = 14
    }
}
