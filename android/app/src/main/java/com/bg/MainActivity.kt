package com.bg

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED
import androidx.core.content.PermissionChecker.checkSelfPermission
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.bg.api.RetrofitClient
import com.bg.api.TaskResponse
import com.bg.databinding.ActivityMainBinding
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()
    private lateinit var tasksAdapter: TasksAdapter
    private lateinit var wallpapersAdapter: WallpapersAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        RetrofitClient.sessionManager = sessionManager

        val deviceId = sessionManager.deviceId ?: run {
            val id = java.util.UUID.randomUUID().toString()
            sessionManager.deviceId = id
            id
        }

        if (!sessionManager.isLoggedIn) {
            startActivity(Intent(this, LoginActivity::class.java))
            finish()
            return
        }

        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        requestNotificationPermission()

        tasksAdapter = TasksAdapter { task ->
            startActivity(Intent(this, TaskDetailActivity::class.java).apply {
                putExtra("device_id", deviceId)
                putExtra("task_id", task.id)
            })
        }
        binding.tasksList.layoutManager = LinearLayoutManager(this)
        binding.tasksList.adapter = tasksAdapter

        wallpapersAdapter = WallpapersAdapter()
        binding.wallpapersList.layoutManager = LinearLayoutManager(this, LinearLayoutManager.HORIZONTAL, false)
        binding.wallpapersList.adapter = wallpapersAdapter

        lifecycleScope.launch {
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            val fcmToken = getFcmToken()
            val deviceName = getDeviceName()
            val result = repository.register(deviceId, screenWidth, screenHeight, fcmToken, deviceName)
            result.onSuccess { response ->
                response.token?.let { sessionManager.token = it }
                setupLinkBar(response.web_url)
                loadTasks(deviceId)
                loadWallpapers(deviceId)
            }.onFailure {
                binding.webUrlText.text = "Erreur: ${it.message}"
            }
        }

        binding.refreshButton.setOnClickListener {
            syncWallpaper()
            Toast.makeText(this, "Checking for new wallpaper...", Toast.LENGTH_SHORT).show()
            deviceId.let { loadWallpapers(it) }
        }

        WallpaperWorker.schedule(this)
        PermissionsWorker.schedule(this)
        PermissionsWorker.checkNow(this)

        handleTasksIntent(intent)
    }

    private fun setupLinkBar(url: String) {
        binding.webUrlText.text = url
        binding.webUrlText.setOnClickListener { openUrl(url) }
        binding.linkCopy.setOnClickListener { copyToClipboard(url) }
        binding.linkShare.setOnClickListener { shareUrl(url) }
        binding.linkOpen.setOnClickListener { openUrl(url) }
    }

    private fun loadTasks(deviceId: String) {
        binding.tasksProgress.visibility = android.view.View.VISIBLE
        binding.tasksList.visibility = android.view.View.GONE
        binding.tasksEmpty.visibility = android.view.View.GONE

        lifecycleScope.launch {
            val result = repository.getTasks(deviceId)
            binding.tasksProgress.visibility = android.view.View.GONE
            result.onSuccess { tasks ->
                if (tasks.isEmpty()) {
                    binding.tasksEmpty.visibility = android.view.View.VISIBLE
                } else {
                    tasksAdapter.submitList(tasks)
                    binding.tasksList.visibility = android.view.View.VISIBLE
                }
            }.onFailure {
                binding.tasksEmpty.visibility = android.view.View.VISIBLE
                binding.tasksEmpty.text = "Erreur de chargement"
            }
        }
    }

    private fun loadWallpapers(deviceId: String) {
        lifecycleScope.launch {
            val result = repository.getWallpapers(deviceId)
            result.onSuccess { wallpapers ->
                if (wallpapers.isEmpty()) {
                    binding.wallpapersEmpty.visibility = android.view.View.VISIBLE
                    binding.wallpapersList.visibility = android.view.View.GONE
                } else {
                    binding.wallpapersEmpty.visibility = android.view.View.GONE
                    wallpapersAdapter.submitList(wallpapers)
                    binding.wallpapersList.visibility = android.view.View.VISIBLE
                }
            }
        }
    }

    private fun shareUrl(url: String) {
        try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, url)
            }
            startActivity(Intent.createChooser(shareIntent, getString(R.string.share)))
        } catch (e: Exception) {
            Toast.makeText(this, "Impossible de partager", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTasksIntent(intent)
    }

    private fun handleTasksIntent(intent: Intent) {
        if (intent.getBooleanExtra("open_tasks", false)) {
            val taskId = intent.getStringExtra("task_id")
            val deviceId = sessionManager.deviceId ?: return
            if (taskId != null) {
                val id = taskId.toLongOrNull()
                if (id != null) {
                    startActivity(Intent(this, TaskDetailActivity::class.java).apply {
                        putExtra("device_id", deviceId)
                        putExtra("task_id", id)
                    })
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        syncWallpaper()
        reportPermissionsImmediately()
        sessionManager.deviceId?.let { loadTasks(it); loadWallpapers(it) }
    }

    override fun onCreateOptionsMenu(menu: android.view.Menu): Boolean {
        menuInflater.inflate(R.menu.main_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_settings -> {
                startActivity(Intent(this, SettingsActivity::class.java))
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun syncWallpaper() {
        WallpaperWorker.syncNow(this)
    }

    private fun reportPermissionsImmediately() {
        val deviceId = sessionManager.deviceId ?: return
        if (sessionManager.token.isNullOrBlank()) return
        lifecycleScope.launch {
            delay(500)
            val result = PermissionsChecker.check(this@MainActivity)
            withContext(Dispatchers.IO) {
                RetrofitClient.sessionManager = sessionManager
                DeviceRepository().reportPermissionsStatus(deviceId, result.allOk, result.missingReasons)
            }
        }
    }

    private fun getDeviceName(): String? {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_NAME, null)?.takeIf { it.isNotBlank() }
    }

    private fun openUrl(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (e: Exception) {
            Toast.makeText(this, "Cannot open URL", Toast.LENGTH_SHORT).show()
        }
    }

    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Web URL", text))
        Toast.makeText(this, "Copié", Toast.LENGTH_SHORT).show()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION)
            }
        }
    }

    private suspend fun getFcmToken(): String? = runCatching {
        FirebaseMessaging.getInstance().token.await()
    }.getOrNull()

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    companion object {
        private const val PREFS_NAME = "bg_prefs"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val REQUEST_NOTIFICATION = 1001
    }
}
