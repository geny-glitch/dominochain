package com.bg

import android.Manifest
import com.bg.api.RetrofitClient
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
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
        PermissionsWorker.schedule(this)
        PermissionsWorker.checkNow(this)

        findViewById<View>(R.id.tasks_button)?.setOnClickListener {
            startActivity(Intent(this, TasksActivity::class.java))
        }

        setupScreenshotSwitch()
        setupBatteryOptimizationLink()

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
        syncScreenshotSwitchState()
        reportPermissionsImmediately()
    }

    private fun syncScreenshotSwitchState() {
        val switch = findViewById<androidx.appcompat.widget.SwitchCompat>(R.id.screenshot_switch) ?: return
        switch.isChecked = BgAccessibilityService.isEnabled(this)
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

    private fun setupScreenshotSwitch() {
        val switch = findViewById<androidx.appcompat.widget.SwitchCompat>(R.id.screenshot_switch) ?: return
        switch.isChecked = BgAccessibilityService.isEnabled(this)
        switch.setOnCheckedChangeListener { _, _ ->
            openAccessibilitySettings()
            // Revert immediately — real state is reflected in onResume after returning from Settings
            switch.isChecked = BgAccessibilityService.isEnabled(this)
        }
    }

    private fun setupBatteryOptimizationLink() {
        binding.batteryOptimizationLink.setOnClickListener {
            openBatteryOptimizationSettings()
        }
    }

    private fun openBatteryOptimizationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
            } catch (_: Exception) {
                try {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    })
                } catch (_: Exception) {
                    Toast.makeText(this, "Impossible d'ouvrir les réglages batterie", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun openAccessibilitySettings() {
        try {
            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            })
        } catch (_: Exception) {
            Toast.makeText(this, "Impossible d'ouvrir les réglages d'accessibilité", Toast.LENGTH_SHORT).show()
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
