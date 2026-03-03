package com.bg

import com.bg.api.RetrofitClient
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.bg.api.TaskResponse
import com.bg.databinding.ActivityTasksBinding
import kotlinx.coroutines.launch

class TasksActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTasksBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val prefs by lazy { getSharedPreferences(WallpaperWorker.PREFS_NAME, MODE_PRIVATE) }
    private val repository = DeviceRepository()
    private lateinit var adapter: TasksAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = sessionManager
        binding = ActivityTasksBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        val deviceId = sessionManager.deviceId ?: prefs.getString(WallpaperWorker.KEY_DEVICE_ID, null)
        if (deviceId == null) {
            Toast.makeText(this, "Device non enregistré", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        adapter = TasksAdapter { task ->
            val intent = Intent(this, TaskDetailActivity::class.java).apply {
                putExtra("device_id", deviceId)
                putExtra("task_id", task.id)
            }
            startActivity(intent)
        }
        binding.tasksList.layoutManager = LinearLayoutManager(this)
        binding.tasksList.adapter = adapter

        loadTasks(deviceId)

        val taskIdFromIntent = intent.getStringExtra("task_id")
        if (taskIdFromIntent != null) {
            val taskId = taskIdFromIntent.toLongOrNull()
            if (taskId != null) {
                val intent = Intent(this, TaskDetailActivity::class.java).apply {
                    putExtra("device_id", deviceId)
                    putExtra("task_id", taskId)
                }
                startActivity(intent)
            }
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun loadTasks(deviceId: String) {
        binding.tasksProgress.visibility = View.VISIBLE
        binding.tasksList.visibility = View.GONE
        binding.tasksEmpty.visibility = View.GONE

        lifecycleScope.launch {
            val result = repository.getTasks(deviceId)
            binding.tasksProgress.visibility = View.GONE
            result.onSuccess { tasks ->
                if (tasks.isEmpty()) {
                    binding.tasksEmpty.visibility = View.VISIBLE
                } else {
                    adapter.submitList(tasks)
                    binding.tasksList.visibility = View.VISIBLE
                }
            }.onFailure {
                Toast.makeText(this@TasksActivity, "Erreur: ${it.message}", Toast.LENGTH_SHORT).show()
                binding.tasksEmpty.visibility = View.VISIBLE
                binding.tasksEmpty.text = "Erreur de chargement"
            }
        }
    }
}
