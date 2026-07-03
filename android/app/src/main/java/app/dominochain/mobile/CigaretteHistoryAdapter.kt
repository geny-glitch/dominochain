package app.dominochain.mobile

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import app.dominochain.mobile.databinding.ItemCigaretteHistoryRowBinding
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

class CigaretteHistoryAdapter(
    private val trackerRepository: TrackerRepository,
    private val trackerType: TrackerType
) : RecyclerView.Adapter<CigaretteHistoryAdapter.VH>() {

    private val dayFormatter = DateTimeFormatter.ofPattern("EEEE d MMM", Locale.FRENCH)
    private val items = mutableListOf<TrackerSnapshot>()
    private var hasMore = true
    private val pageSize = 14

    fun resetAndLoadFirstPage() {
        items.clear()
        val page = trackerRepository.dailySnapshotsPage(trackerType, 0, pageSize)
        items.addAll(page)
        hasMore = page.isNotEmpty()
        notifyDataSetChanged()
    }

    fun appendNextPage() {
        if (!hasMore) return
        val nextPageIndex = items.size / pageSize
        val page = trackerRepository.dailySnapshotsPage(trackerType, nextPageIndex, pageSize)
        if (page.isEmpty()) {
            hasMore = false
            return
        }
        val start = items.size
        items.addAll(page)
        if (page.size < pageSize) hasMore = false
        notifyItemRangeInserted(start, page.size)
    }

    fun canLoadMore(): Boolean = hasMore

    override fun getItemCount(): Int = items.size

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemCigaretteHistoryRowBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val snapshot = items[position]
        val ctx = holder.itemView.context
        val today = LocalDate.now()
        holder.binding.cigaretteRowDate.text = formatDate(snapshot.date, today, ctx)
        holder.binding.cigaretteRowCount.text = snapshot.count.toString()
        val chasterSec = trackerRepository.chasterSeconds(trackerType, snapshot.date)
        holder.binding.cigaretteRowChaster.text = chasterSec.toString()
    }

    private fun formatDate(date: LocalDate, today: LocalDate, context: android.content.Context): String {
        return if (date == today) {
            context.getString(R.string.tracker_today)
        } else {
            date.format(dayFormatter)
        }
    }

    class VH(val binding: ItemCigaretteHistoryRowBinding) : RecyclerView.ViewHolder(binding.root)
}
