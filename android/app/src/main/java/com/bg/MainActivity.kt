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
import android.view.View
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()
    private val authRepository = AuthRepository()
    private val trackerRepository by lazy { TrackerRepository(this) }
    private lateinit var tasksAdapter: TasksAdapter
    private lateinit var wallpapersAdapter: WallpapersAdapter
    private var chasterRefreshJob: Job? = null

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
                setupBetaShowcaseLinks()
                loadTasks(deviceId)
                loadWallpapers(deviceId)
                loadChasterLock()
            }.onFailure {
                binding.webUrlText.text = "Erreur: ${it.message}"
            }
        }

        binding.refreshButton.setOnClickListener {
            syncWallpaper()
            Toast.makeText(this, "Checking for new wallpaper...", Toast.LENGTH_SHORT).show()
            deviceId.let { loadWallpapers(it) }
        }

        binding.chasterRefresh.setOnClickListener {
            loadChasterLock()
            ChasterWidgetWorker.updateNow(this)
        }
        binding.chasterCard.setOnClickListener {
            startActivity(Intent(this, ChasterHistoryActivity::class.java))
        }
        binding.chasterRemaining.setOnClickListener {
            startActivity(Intent(this, ChasterHistoryActivity::class.java))
        }
        binding.cigarettesIncrement.setOnClickListener {
            incrementCigarettesTracker()
        }
        binding.cigarettesCard.setOnClickListener {
            startActivity(Intent(this, CigaretteHistoryActivity::class.java))
        }

        WallpaperWorker.schedule(this)
        PermissionsWorker.schedule(this)
        PermissionsWorker.checkNow(this)
        refreshTrackers()

        handleTasksIntent(intent)
    }

    private fun setupLinkBar(url: String) {
        binding.webUrlText.text = url
        binding.webUrlText.setOnClickListener { openUrl(url) }
        binding.linkCopy.setOnClickListener { copyToClipboard(url) }
        binding.linkShare.setOnClickListener { shareUrl(url) }
        binding.linkOpen.setOnClickListener { openUrl(url) }
    }

    private fun setupBetaShowcaseLinks() {
        val nick = sessionManager.nickname?.trim().orEmpty()
        if (nick.isEmpty()) return

        val base = com.bg.BuildConfig.API_BASE_URL.trimEnd('/')
        val vitrineUrl = "$base/showcase/$nick"
        val backdoorUrl = "$base/showcase/$nick/backdoor"

        lifecycleScope.launch {
            val me = authRepository.getMe().getOrNull() ?: return@launch
            val isBeta = me.role == null || me.role == "beta"
            if (!isBeta) return@launch

            val settings = authRepository.getShowcaseSettings().getOrNull()
            val backdoorOn = settings?.showcase_backdoor_enabled == true

            binding.betaShowcaseSection.visibility = View.VISIBLE
            binding.showcaseLinkVitrine.setOnClickListener { openUrl(vitrineUrl) }
            if (backdoorOn) {
                binding.showcaseLinkBackdoor.visibility = View.VISIBLE
                binding.showcaseLinkBackdoor.setOnClickListener { openUrl(backdoorUrl) }
            } else {
                binding.showcaseLinkBackdoor.visibility = View.GONE
            }
        }
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

    private fun refreshTrackers() {
        val cigarettes = trackerRepository.snapshot(TrackerType.Cigarettes)
        binding.cigarettesCount.text = cigarettes.count.toString()
        binding.cigarettesUnit.text = cigarettes.type.unitLabel
        CigaretteTrackerWidgetProvider.updateWidgets(this)
        CigaretteQuickAddWidgetProvider.updateWidgets(this)

        lifecycleScope.launch {
            val remote = trackerRepository.refreshRemote().getOrNull() ?: return@launch
            binding.cigarettesCount.text = remote.count.toString()
            binding.cigarettesUnit.text = remote.type.unitLabel
            CigaretteTrackerWidgetProvider.updateWidgets(this@MainActivity)
            CigaretteQuickAddWidgetProvider.updateWidgets(this@MainActivity)
        }
    }

    private fun incrementCigarettesTracker() {
        lifecycleScope.launch {
            val snapshot = if (sessionManager.isLoggedIn) {
                trackerRepository.incrementRemote().getOrElse {
                    Toast.makeText(this@MainActivity, "Backend indisponible: cigarette non envoyée", Toast.LENGTH_SHORT).show()
                    return@launch
                }
            } else {
                trackerRepository.increment(TrackerType.Cigarettes)
            }
            binding.cigarettesCount.text = snapshot.count.toString()
            binding.cigarettesUnit.text = snapshot.type.unitLabel
            CigaretteTrackerWidgetProvider.updateWidgets(this@MainActivity)
            CigaretteQuickAddWidgetProvider.updateWidgets(this@MainActivity)
            Toast.makeText(this@MainActivity, "+1 cigarette", Toast.LENGTH_SHORT).show()
        }
    }

    private fun loadChasterLock() {
        lifecycleScope.launch {
            val result = repository.getChasterLock()
            result.onSuccess { response ->
                ChasterWidgetProvider.updateFromLock(
                    this@MainActivity,
                    response?.lock,
                    response?.error,
                    response?.pishock_enabled == true,
                    response?.showcase_quiz_seconds_per_point,
                    response?.showcase_snake_seconds_per_fruit,
                    response?.showcase_dino_seconds_per_obstacle,
                    response?.showcase_tetris_seconds_per_line
                )
                val quizSec = response?.showcase_quiz_seconds_per_point?.takeIf { it > 0 }
                val snakeSec = response?.showcase_snake_seconds_per_fruit?.takeIf { it > 0 }
                val dinoSec = response?.showcase_dino_seconds_per_obstacle?.takeIf { it > 0 }
                val tetrisSec = response?.showcase_tetris_seconds_per_line?.takeIf { it > 0 }
                val gameSecondsText = listOfNotNull(
                    quizSec?.let { "Q: $it" },
                    snakeSec?.let { "S: $it" },
                    dinoSec?.let { "D: $it" },
                    tetrisSec?.let { "T: $it" }
                ).joinToString("  ")
                if (gameSecondsText.isNotEmpty()) {
                    binding.chasterSnakeSeconds.visibility = android.view.View.VISIBLE
                    binding.chasterSnakeSeconds.text = gameSecondsText
                } else {
                    binding.chasterSnakeSeconds.visibility = android.view.View.GONE
                }
                val card = binding.chasterCard
                val lock = response?.lock
                val error = response?.error
                when {
                    lock != null -> {
                        card.visibility = android.view.View.VISIBLE
                        // Utiliser remaining_seconds pour calculer la fin locale (évite la dérive serveur/appareil)
                        val remainingSec = lock.remaining_seconds ?: 0
                        val localEndTimeMs = System.currentTimeMillis() + remainingSec * 1000L
                        card.tag = ChasterLockDisplay(lock, localEndTimeMs)
                        binding.chasterLockTitle.text = lock.title?.takeIf { it.isNotBlank() } ?: "Lock en cours"
                        binding.chasterRemaining.text = formatRemainingTime(lock)
                        binding.chasterHint.visibility = android.view.View.GONE
                        scheduleChasterRefresh() // décompte en temps réel, ne pas annuler
                    }
                    error != null -> {
                        chasterRefreshJob?.cancel()
                        card.visibility = android.view.View.VISIBLE
                        binding.chasterLockTitle.text = "Chaster"
                        binding.chasterRemaining.text = "Non connecté"
                        binding.chasterHint.visibility = android.view.View.VISIBLE
                        binding.chasterHint.text = "Connecte Chaster depuis le dashboard web"
                    }
                    else -> {
                        chasterRefreshJob?.cancel()
                        // Connecté mais aucun lock
                        card.visibility = android.view.View.VISIBLE
                        binding.chasterLockTitle.text = "Chaster"
                        binding.chasterRemaining.text = "Aucun lock en cours"
                        binding.chasterHint.visibility = android.view.View.GONE
                    }
                }
            }.onFailure {
                binding.chasterCard.visibility = android.view.View.GONE
                chasterRefreshJob?.cancel()
            }
        }
    }

    private fun scheduleChasterRefresh() {
        chasterRefreshJob?.cancel()
        chasterRefreshJob = lifecycleScope.launch {
            while (true) {
                delay(1000) // 1 seconde pour mettre à jour le compte à rebours
                val display = binding.chasterCard.tag as? ChasterLockDisplay ?: break
                if (display.lock.is_frozen) break
                val remaining = ((display.localEndTimeMs - System.currentTimeMillis()) / 1000).toInt()
                if (remaining <= 0) {
                    loadChasterLock() // recharger pour mettre à jour
                    break
                }
                binding.chasterRemaining.text = formatRemainingFromSeconds(remaining)
            }
        }
    }

    private data class ChasterLockDisplay(
        val lock: com.bg.api.ChasterLock,
        val localEndTimeMs: Long
    )

    private fun formatRemainingFromSeconds(sec: Int): String {
        if (sec <= 0) return "Terminé"
        val days = sec / 86400
        val hours = (sec % 86400) / 3600
        val mins = (sec % 3600) / 60
        val secs = sec % 60
        return when {
            days > 0 -> "${days}j ${hours}h ${mins}min ${secs}s"
            hours > 0 -> "${hours}h ${mins}min ${secs}s"
            mins > 0 -> "${mins}min ${secs}s"
            else -> "${secs}s"
        }
    }

    private fun formatRemainingTime(lock: com.bg.api.ChasterLock): String {
        if (lock.is_frozen) return "Gelé"
        val sec = lock.remaining_seconds ?: return "--"
        return formatRemainingFromSeconds(sec)
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
        AppUpdateManager(this).checkForUpdates()
        syncWallpaper()
        reportPermissionsImmediately()
        refreshTrackers()
        sessionManager.deviceId?.let {
            loadTasks(it)
            loadWallpapers(it)
            loadChasterLock()
        }
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
