package com.bg

import android.Manifest
import com.bg.api.RetrofitClient
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

        lifecycleScope.launch {
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            val fcmToken = getFcmToken()
            val deviceName = getDeviceName()
            val result = repository.register(deviceId, screenWidth, screenHeight, fcmToken, deviceName)
            result.onSuccess { response ->
                response.token?.let { sessionManager.token = it }
                val webUrl = response.web_url
                binding.webUrlText.text = webUrl
                binding.webUrlText.setOnClickListener {
                    openUrl(webUrl)
                }
                binding.copyButton.setOnClickListener {
                    copyToClipboard(webUrl)
                }
                binding.refreshButton.setOnClickListener {
                    syncWallpaper()
                    Toast.makeText(this@MainActivity, "Checking for new wallpaper...", Toast.LENGTH_SHORT).show()
                }
            }.onFailure {
                binding.webUrlText.text = "Erreur: ${it.message}"
            }
        }

        WallpaperWorker.schedule(this)
        PermissionsWorker.schedule(this)
        PermissionsWorker.checkNow(this)

        binding.tasksButton.setOnClickListener {
            startActivity(Intent(this, TasksActivity::class.java))
        }

        handleTasksIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTasksIntent(intent)
    }

    private fun handleTasksIntent(intent: Intent) {
        if (intent.getBooleanExtra("open_tasks", false)) {
            val taskId = intent.getStringExtra("task_id")
            startActivity(Intent(this, TasksActivity::class.java).apply {
                putExtra("task_id", taskId)
            })
        }
    }

    override fun onResume() {
        super.onResume()
        syncWallpaper()
        reportPermissionsImmediately()
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

    private fun saveDeviceName(name: String?) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_DEVICE_NAME, name ?: "").apply()
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
        Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
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
