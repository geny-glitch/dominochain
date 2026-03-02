package com.bg

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.bg.databinding.ActivityMainBinding
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val prefs by lazy { getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
    private val repository = DeviceRepository()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val deviceId = getOrCreateDeviceId()
        binding.deviceIdText.text = deviceId

        lifecycleScope.launch {
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            val result = repository.register(deviceId, screenWidth, screenHeight)
            result.onSuccess { response ->
                binding.webUrlText.text = response.web_url
                binding.webUrlText.setOnClickListener {
                    openUrl(response.web_url)
                }
                binding.copyButton.setOnClickListener {
                    copyToClipboard(response.web_url)
                }
                binding.refreshButton.setOnClickListener {
                    syncWallpaper()
                    Toast.makeText(this@MainActivity, "Checking for new wallpaper...", Toast.LENGTH_SHORT).show()
                }
            }.onFailure {
                binding.webUrlText.text = "Failed to register: ${it.message}"
            }
        }

        WallpaperWorker.schedule(this)
    }

    override fun onResume() {
        super.onResume()
        syncWallpaper()
    }

    private fun syncWallpaper() {
        WallpaperWorker.syncNow(this)
    }

    private fun getOrCreateDeviceId(): String {
        var deviceId = prefs.getString(KEY_DEVICE_ID, null)
        if (deviceId == null) {
            deviceId = java.util.UUID.randomUUID().toString()
            prefs.edit().putString(KEY_DEVICE_ID, deviceId).apply()
        }
        return deviceId
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

    companion object {
        private const val PREFS_NAME = "bg_prefs"
        private const val KEY_DEVICE_ID = "device_id"
    }
}
