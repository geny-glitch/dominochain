package app.dominochain.mobile

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.dominochain.mobile.databinding.ActivityCigaretteHistoryBinding
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class CigaretteHistoryActivity : AppCompatActivity() {

    private lateinit var binding: ActivityCigaretteHistoryBinding
    private val trackerRepository by lazy { TrackerRepository(this) }
    private val dayFormatter by lazy {
        DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.FRENCH)
    }
    private lateinit var historyAdapter: CigaretteHistoryAdapter
    private var loadingMoreHistory = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCigaretteHistoryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        historyAdapter = CigaretteHistoryAdapter(trackerRepository, TrackerType.Cigarettes)
        binding.cigaretteHistoryRecycler.layoutManager = LinearLayoutManager(this)
        binding.cigaretteHistoryRecycler.adapter = historyAdapter
        val lm = binding.cigaretteHistoryRecycler.layoutManager as LinearLayoutManager
        binding.cigaretteHistoryRecycler.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0 || loadingMoreHistory) return
                val lastVisible = lm.findLastVisibleItemPosition()
                val total = historyAdapter.itemCount
                if (total > 0 && lastVisible >= total - 4 && historyAdapter.canLoadMore()) {
                    loadingMoreHistory = true
                    historyAdapter.appendNextPage()
                    binding.cigaretteHistoryRecycler.post { loadingMoreHistory = false }
                }
            }
        })

        binding.cigaretteHistoryIncrement.setOnClickListener {
            incrementRemote()
        }

        refreshHistory()
        refreshRemote()
    }

    override fun onResume() {
        super.onResume()
        refreshHistory()
        refreshRemote()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun refreshHistory() {
        val today = LocalDate.now()
        val todaySnapshot = trackerRepository.snapshot(TrackerType.Cigarettes)
        binding.cigaretteHistoryTodayCount.text = todaySnapshot.count.toString()
        binding.cigaretteHistoryTodayLabel.text = getString(
            R.string.tracker_cigarettes_today_label,
            formatDate(todaySnapshot.date, today)
        )

        val last7 = trackerRepository.dailySnapshots(TrackerType.Cigarettes, 7)
        val chartEntries = last7.reversed().map { snap ->
            CigaretteHistoryBarChartView.BarEntry(
                snap.date,
                snap.count,
                snap.date == today
            )
        }
        binding.cigaretteHistoryChart.setEntries(chartEntries)

        historyAdapter.resetAndLoadFirstPage()
    }

    private fun formatDate(date: LocalDate, today: LocalDate): String {
        return if (date == today) {
            getString(R.string.tracker_today)
        } else {
            date.format(dayFormatter)
        }
    }

    private fun refreshRemote() {
        lifecycleScope.launch {
            trackerRepository.refreshRemote()
            refreshHistory()
            CigaretteTrackerWidgetProvider.updateWidgets(this@CigaretteHistoryActivity)
            CigaretteQuickAddWidgetProvider.updateWidgets(this@CigaretteHistoryActivity)
        }
    }

    private fun incrementRemote() {
        lifecycleScope.launch {
            if ((application as BgApplication).sessionManager.isLoggedIn) {
                trackerRepository.incrementRemote().getOrNull()
            } else {
                trackerRepository.increment(TrackerType.Cigarettes)
            }
            refreshHistory()
            CigaretteTrackerWidgetProvider.updateWidgets(this@CigaretteHistoryActivity)
            CigaretteQuickAddWidgetProvider.updateWidgets(this@CigaretteHistoryActivity)
        }
    }
}
