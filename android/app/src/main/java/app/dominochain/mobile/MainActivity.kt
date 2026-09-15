package app.dominochain.mobile

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED
import androidx.core.content.PermissionChecker.checkSelfPermission
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityMainBinding
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class MainActivity : BetaShellActivity() {

    private lateinit var binding: ActivityMainBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()

    override val navDestination = AppNavDestination.HOME

    override fun onCreate(savedInstanceState: Bundle?) {
        if (!(application as BgApplication).sessionManager.isLoggedIn) {
            startActivity(Intent(this, LoginActivity::class.java))
            finish()
            return
        }
        val deviceId = sessionManager.deviceId
        if (deviceId.isNullOrBlank()) {
            sessionManager.deviceId = java.util.UUID.randomUUID().toString()
        }
        super.onCreate(savedInstanceState)
    }

    override fun onCreateContent(container: FrameLayout) {
        binding = ActivityMainBinding.inflate(layoutInflater, container, true)

        val deviceId = sessionManager.deviceId!!

        requestNotificationPermission()

        lifecycleScope.launch {
            val displayMetrics = resources.displayMetrics
            val fcmToken = getFcmToken()
            val deviceName = getDeviceName()
            val result = repository.register(
                deviceId,
                displayMetrics.widthPixels,
                displayMetrics.heightPixels,
                fcmToken,
                deviceName
            )
            result.onSuccess { response ->
                response.token?.let { sessionManager.token = it }
                setupLinkBar(response.web_url)
                refreshTasksSummary(deviceId)
            }.onFailure {
                binding.webUrlText.text = getString(R.string.error_with_message, it.message)
            }
        }

        binding.refreshButton.setOnClickListener {
            syncWallpaper()
            Toast.makeText(this, R.string.wallpaper_checking, Toast.LENGTH_SHORT).show()
        }
        binding.homeTasksCard.setOnClickListener {
            openDestination(AppNavDestination.TASKS)
        }

        WallpaperWorker.schedule(this)
        AppUpdateCheckWorker.schedule(this)
        PermissionsWorker.schedule(this)
        PermissionsWorker.checkNow(this)

        handleTasksIntent(intent)
    }

    override fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) {
        binding.homeTasksCard.visibility =
            if (config.sectionVisible("tasks")) View.VISIBLE else View.GONE
    }

    private fun setupLinkBar(url: String) {
        binding.webUrlText.text = url
        binding.webUrlText.setOnClickListener { openUrl(url) }
        binding.linkCopy.setOnClickListener { copyToClipboard(url) }
        binding.linkShare.setOnClickListener { shareUrl(url) }
        binding.linkOpen.setOnClickListener { openUrl(url) }
    }

    private fun refreshTasksSummary(deviceId: String) {
        lifecycleScope.launch {
            val tasks = repository.getTasks(deviceId).getOrNull().orEmpty()
            binding.homeTasksSummary.text = if (tasks.isEmpty()) {
                getString(R.string.tasks_empty)
            } else {
                getString(R.string.home_tasks_count, tasks.size)
            }
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
                    return
                }
            }
            openDestination(AppNavDestination.TASKS)
        }
    }

    override fun onResume() {
        super.onResume()
        AppUpdateManager(this).checkForUpdates()
        syncWallpaper()
        reportPermissionsImmediately()
        sessionManager.deviceId?.let { refreshTasksSummary(it) }
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
            Toast.makeText(this, R.string.open_url_failed, Toast.LENGTH_SHORT).show()
        }
    }

    private fun copyToClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(getString(R.string.clipboard_label_web_url), text))
        Toast.makeText(this, R.string.copied, Toast.LENGTH_SHORT).show()
    }

    private fun shareUrl(url: String) {
        try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, url)
            }
            startActivity(Intent.createChooser(shareIntent, getString(R.string.share)))
        } catch (e: Exception) {
            Toast.makeText(this, R.string.share_failed, Toast.LENGTH_SHORT).show()
        }
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

    companion object {
        private const val PREFS_NAME = "bg_prefs"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val REQUEST_NOTIFICATION = 1001
    }
}
