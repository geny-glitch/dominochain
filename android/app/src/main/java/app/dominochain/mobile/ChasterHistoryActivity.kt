package app.dominochain.mobile

import android.view.View
import android.widget.FrameLayout
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.dominochain.mobile.databinding.ActivityChasterHistoryBinding
import kotlinx.coroutines.launch

class ChasterHistoryActivity : BetaShellActivity() {

    private lateinit var binding: ActivityChasterHistoryBinding
    private val repository = DeviceRepository()
    private val adapter = ChasterTimeEventAdapter()
    private var nextPage = 1
    private var loading = false
    private var hasMore = true

    override val navDestination = AppNavDestination.ACTION_CHASTER

    override fun onCreateContent(container: FrameLayout) {
        binding = ActivityChasterHistoryBinding.inflate(layoutInflater, container, true)

        binding.chasterHistoryRecycler.layoutManager = LinearLayoutManager(this)
        binding.chasterHistoryRecycler.adapter = adapter
        val layoutManager = binding.chasterHistoryRecycler.layoutManager as LinearLayoutManager
        binding.chasterHistoryRecycler.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (dy <= 0 || loading || !hasMore) return
                val lastVisible = layoutManager.findLastVisibleItemPosition()
                if (lastVisible >= adapter.itemCount - 4) {
                    loadNextPage()
                }
            }
        })

        loadNextPage(reset = true)
    }

    override fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) {
        if (!config.actionEnabled("chaster") || !config.sectionVisible("chaster")) {
            openDestination(AppNavDestination.HOME)
        }
    }

    private fun loadNextPage(reset: Boolean = false) {
        if (loading) return
        if (reset) {
            adapter.clear()
            nextPage = 1
            hasMore = true
            binding.chasterHistoryStatus.visibility = View.GONE
        }
        if (!hasMore) return

        loading = true
        if (adapter.itemCount == 0) {
            binding.chasterHistoryProgress.visibility = View.VISIBLE
        }

        lifecycleScope.launch {
            val result = repository.getChasterTimeEvents(nextPage, PAGE_SIZE)
            binding.chasterHistoryProgress.visibility = View.GONE
            loading = false

            result.onSuccess { response ->
                adapter.appendEvents(response.events)
                nextPage = response.meta?.next_page ?: (nextPage + 1)
                hasMore = response.meta?.next_page != null
                updateStatus()
            }.onFailure {
                binding.chasterHistoryStatus.visibility = View.VISIBLE
                binding.chasterHistoryStatus.text = getString(R.string.chaster_history_load_error)
            }
        }
    }

    private fun updateStatus() {
        val message = when {
            adapter.itemCount == 0 -> getString(R.string.chaster_history_empty)
            hasMore -> null
            else -> getString(R.string.chaster_history_end)
        }
        binding.chasterHistoryStatus.visibility = if (message == null) {
            View.GONE
        } else {
            View.VISIBLE
        }
        if (message != null) binding.chasterHistoryStatus.text = message
    }

    companion object {
        private const val PAGE_SIZE = 20
    }
}
