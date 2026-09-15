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
        holder.binding.chasterEventSource.text = event.source_label ?: event.source
            ?: ctx.getString(R.string.chaster_title)
        holder.binding.chasterEventDate.text = formatDate(ctx, event.occurred_at)
        holder.binding.chasterEventSummary.text = event.summary?.takeIf { it.isNotBlank() }
            ?: ctx.getString(R.string.chaster_history_default_summary)
        holder.binding.chasterEventSeconds.text = formatSeconds(ctx, event.seconds)
        holder.binding.chasterEventSeconds.setTextColor(
            ContextCompat.getColor(ctx, if (event.seconds >= 0) R.color.ds_teal else R.color.ds_error)
        )
    }

    private fun formatDate(ctx: android.content.Context, raw: String?): String {
        if (raw.isNullOrBlank()) return ctx.getString(R.string.chaster_remaining_placeholder)
        return runCatching {
            OffsetDateTime.parse(raw)
                .atZoneSameInstant(ZoneId.systemDefault())
                .format(dateFormatter)
        }.getOrDefault(raw)
    }

    private fun formatSeconds(ctx: android.content.Context, seconds: Int): String {
        val sign = if (seconds >= 0) "+" else "-"
        var remaining = abs(seconds)
        val days = remaining / 86_400
        remaining %= 86_400
        val hours = remaining / 3_600
        remaining %= 3_600
        val minutes = remaining / 60
        val secs = remaining % 60

        val parts = buildList {
            if (days > 0) add(ctx.getString(R.string.duration_unit_days, days))
            if (hours > 0) add(ctx.getString(R.string.duration_unit_hours, hours))
            if (minutes > 0) add(ctx.getString(R.string.duration_unit_mins, minutes))
            if (isEmpty() || secs > 0) add(ctx.getString(R.string.duration_unit_secs, secs))
        }
        return ctx.getString(R.string.duration_signed, sign, parts.joinToString(" "))
    }

    class VH(val binding: ItemChasterTimeEventBinding) : RecyclerView.ViewHolder(binding.root)
}
