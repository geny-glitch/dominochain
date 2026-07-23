package app.dominochain.mobile

import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.LeveragePhotoResponse
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityLeveragePhotoDetailBinding
import coil.load
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant

class LeveragePhotoDetailActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLeveragePhotoDetailBinding
    private val repository = LeveragePhotoRepository()
    private var photoId: Long = 0
    private var photo: LeveragePhotoResponse? = null
    private var tlockBridge: TlockBridge? = null
    private var countdownJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = (application as BgApplication).sessionManager
        binding = ActivityLeveragePhotoDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.leverage_photos_title)

        photoId = intent.getLongExtra(EXTRA_PHOTO_ID, 0L)
        if (photoId == 0L) {
            finish()
            return
        }

        tlockBridge = TlockBridge(this)

        binding.leverageStartTimerButton.setOnClickListener { startTimer() }
        binding.leverageAddTimeButton.setOnClickListener { addTime() }
        binding.leverageSetTeaserWallpaper.setOnClickListener { setWallpaper("teaser") }
        binding.leverageSetCensoredWallpaper.setOnClickListener { setWallpaper("censored") }
        binding.leverageDecryptButton.setOnClickListener { decryptAndRestore() }

        loadPhoto()
    }

    override fun onDestroy() {
        countdownJob?.cancel()
        tlockBridge?.destroy()
        super.onDestroy()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun loadPhoto() {
        lifecycleScope.launch {
            repository.get(photoId)
                .onSuccess { applyPhoto(it) }
                .onFailure {
                    Toast.makeText(this@LeveragePhotoDetailActivity, it.message, Toast.LENGTH_LONG).show()
                }
        }
    }

    private fun applyPhoto(p: LeveragePhotoResponse) {
        photo = p
        binding.leverageDetailStatus.text = getString(R.string.leverage_detail_status, p.status, p.tlock_layer_count)
        val imageUrl = p.censored_url ?: p.teaser_url
        if (imageUrl != null) {
            binding.leverageDetailImage.load(imageUrl)
        }
        binding.leverageStartTimerButton.isEnabled = p.can_start_timer
        binding.leverageAddTimeButton.isEnabled = p.can_add_time
        binding.leverageSetTeaserWallpaper.isEnabled = p.has_teaser && p.wallpaper_ready
        binding.leverageSetCensoredWallpaper.isEnabled = p.has_censored && p.wallpaper_ready
        binding.leverageDecryptButton.isEnabled = p.status == "unlocked" || p.status == "active"
        startCountdown(p.locked_until)
    }

    private fun startCountdown(lockedUntilIso: String?) {
        countdownJob?.cancel()
        if (lockedUntilIso.isNullOrBlank()) {
            binding.leverageDetailCountdown.visibility = View.GONE
            return
        }
        binding.leverageDetailCountdown.visibility = View.VISIBLE
        val endMs = runCatching { Instant.parse(lockedUntilIso).toEpochMilli() }.getOrNull() ?: return
        countdownJob = lifecycleScope.launch {
            while (true) {
                val remaining = ((endMs - System.currentTimeMillis()) / 1000).toInt()
                if (remaining <= 0) {
                    binding.leverageDetailCountdown.setText(R.string.leverage_ready_to_unlock)
                    break
                }
                binding.leverageDetailCountdown.text = getString(
                    R.string.leverage_countdown,
                    formatRemaining(remaining)
                )
                delay(1000)
            }
        }
    }

    private fun formatRemaining(sec: Int): String {
        val d = sec / 86400
        val h = (sec % 86400) / 3600
        val m = (sec % 3600) / 60
        val s = sec % 60
        return when {
            d > 0 -> "${d}d ${h}h ${m}m"
            h > 0 -> "${h}h ${m}m ${s}s"
            else -> "${m}m ${s}s"
        }
    }

    private fun startTimer() {
        val minutes = binding.leverageDurationMinutes.text.toString().toIntOrNull()
        if (minutes == null || minutes < 1) {
            Toast.makeText(this, R.string.leverage_invalid_duration, Toast.LENGTH_SHORT).show()
            return
        }
        binding.leverageStartTimerButton.isEnabled = false
        binding.leverageCryptoStatus.setText(R.string.leverage_securing)
        lifecycleScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    val bridge = tlockBridge ?: throw IllegalStateException("Crypto unavailable")
                    if (!bridge.ensureReady()) throw IllegalStateException("Crypto library failed to load")
                    val originalBytes = repository.downloadOriginal(photoId).getOrThrow()
                    val lockedUntilMs = System.currentTimeMillis() + minutes * 60_000L
                    val encrypted = bridge.encryptBytes(originalBytes, lockedUntilMs)
                    val tlockFile = File(cacheDir, "layer_${System.currentTimeMillis()}.tlock")
                    tlockFile.writeText(encrypted.armored)
                    Triple(encrypted, tlockFile, lockedUntilMs)
                }
                val (encrypted, tlockFile, lockedUntilMs) = result
                val lockedUntilIso = Instant.ofEpochMilli(lockedUntilMs).toString()
                repository.startTimer(
                    id = photoId,
                    tlockFile = tlockFile,
                    drandRound = encrypted.round,
                    lockedUntilIso = lockedUntilIso,
                    durationSeconds = minutes * 60,
                    chainHash = encrypted.chainHash
                ).onSuccess {
                    Toast.makeText(this@LeveragePhotoDetailActivity, R.string.leverage_timer_started, Toast.LENGTH_SHORT).show()
                    it.photo?.let { applyPhoto(it) } ?: loadPhoto()
                }.onFailure {
                    Toast.makeText(this@LeveragePhotoDetailActivity, it.message, Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                Toast.makeText(this@LeveragePhotoDetailActivity, e.message, Toast.LENGTH_LONG).show()
            } finally {
                binding.leverageCryptoStatus.text = ""
                binding.leverageStartTimerButton.isEnabled = photo?.can_start_timer == true
            }
        }
    }

    private fun addTime() {
        val minutes = binding.leverageDurationMinutes.text.toString().toIntOrNull()
        if (minutes == null || minutes < 1) {
            Toast.makeText(this, R.string.leverage_invalid_duration, Toast.LENGTH_SHORT).show()
            return
        }
        val current = photo ?: return
        binding.leverageAddTimeButton.isEnabled = false
        binding.leverageCryptoStatus.setText(R.string.leverage_securing)
        lifecycleScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    val bridge = tlockBridge ?: throw IllegalStateException("Crypto unavailable")
                    if (!bridge.ensureReady()) throw IllegalStateException("Crypto library failed to load")
                    val currentArmored = String(repository.downloadTlockBlob(photoId).getOrThrow(), Charsets.UTF_8)
                    val baseMs = current.locked_until?.let {
                        runCatching { Instant.parse(it).toEpochMilli() }.getOrNull()
                    } ?: System.currentTimeMillis()
                    val fromMs = maxOf(baseMs, System.currentTimeMillis())
                    val lockedUntilMs = fromMs + minutes * 60_000L
                    val encrypted = bridge.encryptOuter(currentArmored, lockedUntilMs)
                    val tlockFile = File(cacheDir, "layer_${System.currentTimeMillis()}.tlock")
                    tlockFile.writeText(encrypted.armored)
                    Triple(encrypted, tlockFile, lockedUntilMs)
                }
                val (encrypted, tlockFile, lockedUntilMs) = result
                repository.addTime(
                    id = photoId,
                    tlockFile = tlockFile,
                    drandRound = encrypted.round,
                    lockedUntilIso = Instant.ofEpochMilli(lockedUntilMs).toString(),
                    addedSeconds = minutes * 60
                ).onSuccess {
                    Toast.makeText(this@LeveragePhotoDetailActivity, R.string.leverage_time_added, Toast.LENGTH_SHORT).show()
                    it.photo?.let { applyPhoto(it) } ?: loadPhoto()
                }.onFailure {
                    Toast.makeText(this@LeveragePhotoDetailActivity, it.message, Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                Toast.makeText(this@LeveragePhotoDetailActivity, e.message, Toast.LENGTH_LONG).show()
            } finally {
                binding.leverageCryptoStatus.text = ""
                binding.leverageAddTimeButton.isEnabled = photo?.can_add_time == true
            }
        }
    }

    private fun setWallpaper(variant: String) {
        lifecycleScope.launch {
            repository.setAsWallpaper(photoId, variant)
                .onSuccess {
                    Toast.makeText(this@LeveragePhotoDetailActivity, R.string.leverage_wallpaper_set, Toast.LENGTH_SHORT).show()
                    WallpaperWorker.syncNow(this@LeveragePhotoDetailActivity, forceRefresh = true)
                    it.photo?.let { applyPhoto(it) }
                }
                .onFailure {
                    Toast.makeText(this@LeveragePhotoDetailActivity, it.message, Toast.LENGTH_LONG).show()
                }
        }
    }

    private fun decryptAndRestore() {
        binding.leverageDecryptButton.isEnabled = false
        binding.leverageCryptoStatus.setText(R.string.leverage_unlocking)
        lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val bridge = tlockBridge ?: throw IllegalStateException("Crypto unavailable")
                    if (!bridge.ensureReady()) throw IllegalStateException("Crypto library failed to load")
                    val armored = String(repository.downloadDecryptPayload(photoId).getOrThrow(), Charsets.UTF_8)
                    val layers = photo?.tlock_layer_count?.coerceAtLeast(1) ?: 1
                    val bytes = bridge.decryptLayers(armored, layers)
                    val file = File(cacheDir, "restored_${System.currentTimeMillis()}.jpg")
                    file.writeBytes(bytes)
                    repository.restoreOriginal(photoId, file).getOrThrow()
                }
                Toast.makeText(this@LeveragePhotoDetailActivity, R.string.leverage_restored, Toast.LENGTH_SHORT).show()
                loadPhoto()
            } catch (e: Exception) {
                Toast.makeText(this@LeveragePhotoDetailActivity, e.message, Toast.LENGTH_LONG).show()
            } finally {
                binding.leverageCryptoStatus.text = ""
                binding.leverageDecryptButton.isEnabled = true
            }
        }
    }

    companion object {
        const val EXTRA_PHOTO_ID = "photo_id"
    }
}
