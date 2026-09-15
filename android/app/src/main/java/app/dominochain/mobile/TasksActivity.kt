package app.dominochain.mobile

import android.content.Intent
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityTasksBinding
import kotlinx.coroutines.launch

class TasksActivity : BetaShellActivity() {

    private lateinit var binding: ActivityTasksBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val prefs by lazy { getSharedPreferences(WallpaperWorker.PREFS_NAME, MODE_PRIVATE) }
    private val repository = DeviceRepository()
    private lateinit var adapter: TasksAdapter

    override val navDestination = AppNavDestination.TASKS

    override fun onCreateContent(container: FrameLayout) {
        RetrofitClient.sessionManager = sessionManager
        binding = ActivityTasksBinding.inflate(layoutInflater, container, true)

        val deviceId = sessionManager.deviceId ?: prefs.getString(WallpaperWorker.KEY_DEVICE_ID, null)
        if (deviceId == null) {
            Toast.makeText(this, R.string.device_not_registered, Toast.LENGTH_SHORT).show()
            openDestination(AppNavDestination.HOME)
            return
        }

        adapter = TasksAdapter { task ->
            startActivity(Intent(this, TaskDetailActivity::class.java).apply {
                putExtra("device_id", deviceId)
                putExtra("task_id", task.id)
            })
        }
        binding.tasksList.layoutManager = LinearLayoutManager(this)
        binding.tasksList.adapter = adapter

        loadTasks(deviceId)

        val taskIdFromIntent = intent.getStringExtra("task_id")
        if (taskIdFromIntent != null) {
            val taskId = taskIdFromIntent.toLongOrNull()
            if (taskId != null) {
                startActivity(Intent(this, TaskDetailActivity::class.java).apply {
                    putExtra("device_id", deviceId)
                    putExtra("task_id", taskId)
                })
            }
        }
    }

    override fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) {
        if (!config.sectionVisible("tasks")) openDestination(AppNavDestination.HOME)
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
                Toast.makeText(this@TasksActivity, getString(R.string.error_with_message, it.message), Toast.LENGTH_SHORT).show()
                binding.tasksEmpty.visibility = View.VISIBLE
                binding.tasksEmpty.text = getString(R.string.tasks_load_error)
            }
        }
    }
}
