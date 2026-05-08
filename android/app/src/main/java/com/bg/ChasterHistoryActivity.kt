package com.bg

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bg.databinding.ActivityChasterHistoryBinding
import kotlinx.coroutines.launch

class ChasterHistoryActivity : AppCompatActivity() {

    private lateinit var binding: ActivityChasterHistoryBinding
    private val repository = DeviceRepository()
    private val adapter = ChasterTimeEventAdapter()
    private var nextPage = 1
    private var loading = false
    private var hasMore = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChasterHistoryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

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

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun loadNextPage(reset: Boolean = false) {
        if (loading) return
        if (reset) {
            adapter.clear()
            nextPage = 1
            hasMore = true
            binding.chasterHistoryStatus.visibility = android.view.View.GONE
        }
        if (!hasMore) return

        loading = true
        if (adapter.itemCount == 0) {
            binding.chasterHistoryProgress.visibility = android.view.View.VISIBLE
        }

        lifecycleScope.launch {
            val result = repository.getChasterTimeEvents(nextPage, PAGE_SIZE)
            binding.chasterHistoryProgress.visibility = android.view.View.GONE
            loading = false

            result.onSuccess { response ->
                adapter.appendEvents(response.events)
                nextPage = response.meta?.next_page ?: (nextPage + 1)
                hasMore = response.meta?.next_page != null
                updateStatus()
            }.onFailure {
                binding.chasterHistoryStatus.visibility = android.view.View.VISIBLE
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
            android.view.View.GONE
        } else {
            android.view.View.VISIBLE
        }
        if (message != null) binding.chasterHistoryStatus.text = message
    }

    companion object {
        private const val PAGE_SIZE = 20
    }
}
