package com.bg

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bg.api.TaskResponse
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TasksAdapter(
    private val onTaskClick: (TaskResponse) -> Unit
) : ListAdapter<TaskResponse, TasksAdapter.ViewHolder>(TaskDiffCallback()) {

    private val dateFormat = SimpleDateFormat("dd/MM HH:mm", Locale.getDefault())

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(android.R.layout.simple_list_item_2, parent, false)
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
            val deadlineStr = try {
                val parser = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }
                val date = parser.parse(task.deadline_at.replace("Z", "").take(19))
                if (date != null) dateFormat.format(date) else task.deadline_at.take(16)
            } catch (_: Exception) {
                task.deadline_at.take(16)
            }
            text2.text = "Deadline: $deadlineStr · ${task.status}"
        }
    }

    class TaskDiffCallback : DiffUtil.ItemCallback<TaskResponse>() {
        override fun areItemsTheSame(oldItem: TaskResponse, newItem: TaskResponse) = oldItem.id == newItem.id
        override fun areContentsTheSame(oldItem: TaskResponse, newItem: TaskResponse) = oldItem == newItem
    }
}
