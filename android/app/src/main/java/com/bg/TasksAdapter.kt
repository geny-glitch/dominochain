package com.bg

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bg.api.TaskResponse
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

class TasksAdapter(
    private val onTaskClick: (TaskResponse) -> Unit
) : ListAdapter<TaskResponse, TasksAdapter.ViewHolder>(TaskDiffCallback()) {

    private val dateFormat = DateTimeFormatter.ofPattern("d MMM à HH'h'mm", Locale.FRENCH)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_task, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val task = getItem(position)
        holder.bind(task)
        holder.itemView.setOnClickListener { onTaskClick(task) }
    }

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val text1: TextView = view.findViewById(android.R.id.text1)
        private val text2: TextView = view.findViewById(android.R.id.text2)

        fun bind(task: TaskResponse) {
            text1.text = task.name
            val deadlineStr = formatDeadline(task.deadline_at)
            text2.text = "Deadline: $deadlineStr · ${task.status}"
        }
    }

    private fun formatDeadline(iso: String): String {
        val zone = ZoneId.systemDefault()
        return try {
            val zdt = try {
                Instant.parse(iso).atZone(zone)
            } catch (_: Exception) {
                ZonedDateTime.parse(iso)
            }
            dateFormat.format(zdt)
        } catch (_: Exception) {
            val m = Regex("(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})").find(iso)
            if (m != null) "${m.groupValues[3]}/${m.groupValues[2]} ${m.groupValues[4]}h${m.groupValues[5]}"
            else iso.replace("T", " ")
        }
    }

    class TaskDiffCallback : DiffUtil.ItemCallback<TaskResponse>() {
        override fun areItemsTheSame(oldItem: TaskResponse, newItem: TaskResponse) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: TaskResponse, newItem: TaskResponse) = oldItem == newItem
    }
}
