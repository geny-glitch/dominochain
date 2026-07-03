package app.dominochain.mobile

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import app.dominochain.mobile.api.ChasterTimeEvent
import app.dominochain.mobile.databinding.ItemChasterTimeEventBinding
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

class ChasterTimeEventAdapter : RecyclerView.Adapter<ChasterTimeEventAdapter.VH>() {

    private val items = mutableListOf<ChasterTimeEvent>()
    private val dateFormatter = DateTimeFormatter.ofPattern("dd/MM HH:mm", Locale.FRENCH)

    fun clear() {
        items.clear()
        notifyDataSetChanged()
    }

    fun appendEvents(events: List<ChasterTimeEvent>) {
        if (events.isEmpty()) return
        val start = items.size
        items.addAll(events)
        notifyItemRangeInserted(start, events.size)
    }

    override fun getItemCount(): Int = items.size

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val binding = ItemChasterTimeEventBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(binding)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val event = items[position]
        val ctx = holder.itemView.context
        holder.binding.chasterEventSource.text = event.source_label ?: event.source ?: "Chaster"
        holder.binding.chasterEventDate.text = formatDate(event.occurred_at)
        holder.binding.chasterEventSummary.text = event.summary?.takeIf { it.isNotBlank() }
            ?: ctx.getString(R.string.chaster_history_default_summary)
        holder.binding.chasterEventSeconds.text = formatSeconds(event.seconds)
        holder.binding.chasterEventSeconds.setTextColor(
            ContextCompat.getColor(ctx, if (event.seconds >= 0) R.color.ds_teal else R.color.ds_error)
        )
    }

    private fun formatDate(raw: String?): String {
        if (raw.isNullOrBlank()) return "--"
        return runCatching {
            OffsetDateTime.parse(raw)
                .atZoneSameInstant(ZoneId.systemDefault())
                .format(dateFormatter)
        }.getOrDefault(raw)
    }

    private fun formatSeconds(seconds: Int): String {
        val sign = if (seconds >= 0) "+" else "-"
        var remaining = abs(seconds)
        val days = remaining / 86_400
        remaining %= 86_400
        val hours = remaining / 3_600
        remaining %= 3_600
        val minutes = remaining / 60
        val secs = remaining % 60

        val parts = buildList {
            if (days > 0) add("${days}j")
            if (hours > 0) add("${hours}h")
            if (minutes > 0) add("${minutes}min")
            if (isEmpty() || secs > 0) add("${secs}s")
        }
        return "$sign${parts.joinToString(" ")}"
    }

    class VH(val binding: ItemChasterTimeEventBinding) : RecyclerView.ViewHolder(binding.root)
}
