package com.bg

import android.Manifest
import com.bg.api.RetrofitClient
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Context.MEDIA_PROJECTION_SERVICE
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED
import androidx.core.content.PermissionChecker.checkSelfPermission
import androidx.lifecycle.lifecycleScope
import com.bg.databinding.ActivityMainBinding
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()
    private val authRepository = AuthRepository()

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

        binding.deviceIdText.text = deviceId

        binding.deviceNameInput.setText(getDeviceName() ?: "")

        binding.saveNameButton.setOnClickListener {
            lifecycleScope.launch {
                val name = binding.deviceNameInput.text.toString().trim().takeIf { it.isNotEmpty() }
                saveDeviceName(name)
                repository.updateName(deviceId, name).onSuccess {
                    Toast.makeText(this@MainActivity, "Nom enregistré", Toast.LENGTH_SHORT).show()
                }.onFailure {
                    Toast.makeText(this@MainActivity, "Erreur: ${it.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }

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

        findViewById<View>(R.id.tasks_button)?.setOnClickListener {
            startActivity(Intent(this, TasksActivity::class.java))
        }

        setupScreenshotSwitch()

        findViewById<View>(R.id.send_control_request_button)?.setOnClickListener {
            val bossNickname = findViewById<android.widget.EditText>(R.id.boss_nickname_input).text.toString().trim()
            if (bossNickname.isBlank()) {
                Toast.makeText(this, "Entrez le pseudo du boss", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            lifecycleScope.launch {
                authRepository.sendControlRequest(bossNickname)
                    .onSuccess { msg ->
                        Toast.makeText(this@MainActivity, msg, Toast.LENGTH_SHORT).show()
                    }
                    .onFailure {
                        Toast.makeText(this@MainActivity, it.message, Toast.LENGTH_SHORT).show()
                    }
            }
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
    }

    private fun syncWallpaper() {
        WallpaperWorker.syncNow(this)
    }

    private fun setupScreenshotSwitch() {
        val switch = findViewById<androidx.appcompat.widget.SwitchCompat>(R.id.screenshot_switch) ?: return
        switch.isChecked = prefs.getBoolean(ScreenshotCaptureService.KEY_SCREENSHOT_ENABLED, false)
        switch.setOnCheckedChangeListener { _, isChecked ->
            if (isChecked) {
                val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
                startActivityForResult(
                    projectionManager.createScreenCaptureIntent(),
                    REQUEST_MEDIA_PROJECTION
                )
            } else {
                prefs.edit().putBoolean(ScreenshotCaptureService.KEY_SCREENSHOT_ENABLED, false).apply()
                stopService(Intent(this, ScreenshotCaptureService::class.java))
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            val switch = findViewById<androidx.appcompat.widget.SwitchCompat>(R.id.screenshot_switch) ?: return
            if (resultCode == RESULT_OK && data != null) {
                prefs.edit().putBoolean(ScreenshotCaptureService.KEY_SCREENSHOT_ENABLED, true).apply()
                val serviceIntent = Intent(this, ScreenshotCaptureService::class.java).apply {
                    action = ScreenshotCaptureService.ACTION_START
                    putExtra(ScreenshotCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenshotCaptureService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            } else {
                switch.isChecked = false
            }
        }
    }

    private fun getDeviceName(): String? {
        return prefs.getString(KEY_DEVICE_NAME, null)?.takeIf { it.isNotBlank() }
    }

    private fun saveDeviceName(name: String?) {
        prefs.edit().putString(KEY_DEVICE_NAME, name ?: "").apply()
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
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val REQUEST_NOTIFICATION = 1001
        private const val REQUEST_MEDIA_PROJECTION = 1002
    }
}
