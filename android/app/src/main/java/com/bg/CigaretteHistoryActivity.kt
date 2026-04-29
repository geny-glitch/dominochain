package com.bg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.bg.databinding.ActivityCigaretteHistoryBinding
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class CigaretteHistoryActivity : AppCompatActivity() {

    private lateinit var binding: ActivityCigaretteHistoryBinding
    private val trackerRepository by lazy { TrackerRepository(this) }
    private val dayFormatter by lazy {
        DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.FRENCH)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCigaretteHistoryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        binding.cigaretteHistoryIncrement.setOnClickListener {
            trackerRepository.increment(TrackerType.Cigarettes)
            refreshHistory()
            CigaretteTrackerWidgetProvider.updateWidgets(this)
            CigaretteQuickAddWidgetProvider.updateWidgets(this)
        }

        refreshHistory()
    }

    override fun onResume() {
        super.onResume()
        refreshHistory()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun refreshHistory() {
        val snapshots = trackerRepository.dailySnapshots(TrackerType.Cigarettes)
        val today = LocalDate.now()
        val todaySnapshot = snapshots.first()
        binding.cigaretteHistoryTodayCount.text = todaySnapshot.count.toString()
        binding.cigaretteHistoryTodayLabel.text = getString(
            R.string.tracker_cigarettes_today_label,
            formatDate(todaySnapshot.date, today)
        )
        binding.cigaretteHistoryRows.text = snapshots.joinToString(separator = "\n") { snapshot ->
            getString(
                R.string.tracker_cigarettes_history_row,
                formatDate(snapshot.date, today),
                snapshot.count
            )
        }
    }

    private fun formatDate(date: LocalDate, today: LocalDate): String {
        return if (date == today) {
            getString(R.string.tracker_today)
        } else {
            date.format(dayFormatter)
        }
    }
}
