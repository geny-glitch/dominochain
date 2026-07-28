package app.dominochain.mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.api.WallpaperActionSchemaDto
import app.dominochain.mobile.api.WallpaperConfigResponse
import app.dominochain.mobile.api.WallpaperConfigUpdateRequest
import app.dominochain.mobile.api.WallpaperScenarioActionDto
import app.dominochain.mobile.api.WallpaperScenarioDto
import app.dominochain.mobile.api.WallpaperScenariosWrapper
import app.dominochain.mobile.databinding.ActivityWallpaperBinding
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class WallpaperActivity : AppCompatActivity() {

    private lateinit var binding: ActivityWallpaperBinding
    private val repository = WallpaperRepository()
    private var config: WallpaperConfigResponse? = null
    private var scenarios: MutableList<WallpaperScenarioDto> = mutableListOf()
    private var eventIds: List<String> = emptyList()
    private var actions: List<WallpaperActionSchemaDto> = emptyList()
    private var durationHours: List<Int> = listOf(1, 2, 4, 8, 12, 24)
    private var updatingUi = false

    private val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri ?: return@registerForActivityResult
        val file = copyToCache(uri) ?: run {
            Toast.makeText(this, R.string.wallpaper_upload_failed, Toast.LENGTH_SHORT).show()
            return@registerForActivityResult
        }
        uploadWallpaper(file)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = (application as BgApplication).sessionManager
        binding = ActivityWallpaperBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.wallpaper_title)

        binding.wallpaperUploadButton.setOnClickListener { pickImage.launch("image/*") }
        binding.wallpaperSaveOptionsButton.setOnClickListener { saveOptions() }
        binding.wallpaperAddScenarioButton.setOnClickListener { addScenario() }
        binding.wallpaperClearScenariosButton.setOnClickListener { clearScenarios() }
        binding.wallpaperStartVerificationButton.setOnClickListener { startVerification() }
        binding.wallpaperOpenLeverageButton.setOnClickListener {
            startActivity(Intent(this, LeveragePhotosActivity::class.java))
        }
        binding.wallpaperEnabledSwitch.setOnCheckedChangeListener { _, checked ->
            if (!updatingUi) toggleEnabled(checked)
        }

        loadAll()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun loadAll() {
        binding.wallpaperStatus.setText(R.string.wallpaper_loading)
        lifecycleScope.launch {
            val schemaResult = repository.getScenarioSchema()
            val configResult = repository.getConfig()
            schemaResult.onSuccess { schema ->
                eventIds = schema.events.keys.toList().ifEmpty {
                    listOf("mismatch", "permissions_lost", "app_unreachable")
                }
                actions = schema.actions
                binding.wallpaperScenarioEvent.adapter = ArrayAdapter(
                    this@WallpaperActivity,
                    android.R.layout.simple_spinner_dropdown_item,
                    eventIds
                )
                binding.wallpaperScenarioAction.adapter = ArrayAdapter(
                    this@WallpaperActivity,
                    android.R.layout.simple_spinner_dropdown_item,
                    actions.map { it.possibility_id }.ifEmpty { listOf("chaster.add_time") }
                )
            }
            configResult.onSuccess { applyConfig(it) }
                .onFailure {
                    binding.wallpaperStatus.text = it.message
                    Toast.makeText(this@WallpaperActivity, it.message, Toast.LENGTH_LONG).show()
                }
        }
    }

    private fun applyConfig(cfg: WallpaperConfigResponse) {
        config = cfg
        scenarios = cfg.scenarios?.scenarios?.toMutableList() ?: mutableListOf()
        durationHours = cfg.allowed_duration_hours.ifEmpty { durationHours }

        updatingUi = true
        binding.wallpaperEnabledSwitch.isChecked = cfg.enabled
        binding.wallpaperIntervalInput.setText(cfg.check_interval_minutes.toString())
        binding.wallpaperDismissAppsSwitch.isChecked = cfg.dismiss_apps_before_capture
        updatingUi = false

        binding.wallpaperVerificationDuration.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            durationHours.map { getString(R.string.wallpaper_verification_hours, it) }
        )

        val device = cfg.device
        binding.wallpaperDeviceStatus.text = buildString {
            if (device?.connected == true) {
                append(getString(R.string.wallpaper_device_connected, device.name ?: "—"))
                append("\n")
                append(
                    if (device.permissions_ok) getString(R.string.wallpaper_permissions_ok)
                    else getString(R.string.wallpaper_permissions_missing, device.permissions_missing.joinToString())
                )
            } else {
                append(getString(R.string.wallpaper_no_device))
            }
        }

        val locked = cfg.locked || cfg.config_locked
        binding.wallpaperUploadButton.isEnabled = !locked && !cfg.boss_controls
        binding.wallpaperEnabledSwitch.isEnabled = !cfg.config_locked
        binding.wallpaperIntervalInput.isEnabled = !cfg.config_locked
        binding.wallpaperDismissAppsSwitch.isEnabled = !cfg.config_locked
        binding.wallpaperSaveOptionsButton.isEnabled = !cfg.config_locked
        binding.wallpaperAddScenarioButton.isEnabled = !cfg.config_locked
        binding.wallpaperClearScenariosButton.isEnabled = !cfg.config_locked
        binding.wallpaperStartVerificationButton.isEnabled =
            !cfg.verification_session?.active.orFalse() && device?.has_current_wallpaper == true

        if (cfg.verification_session?.active == true) {
            binding.wallpaperVerificationStatus.text = getString(
                R.string.wallpaper_verification_active,
                cfg.verification_session.duration_hours ?: 0,
                cfg.verification_session.ends_at ?: "—"
            )
            binding.wallpaperStatus.setText(R.string.wallpaper_locked_hint)
        } else if (cfg.boss_controls) {
            binding.wallpaperVerificationStatus.setText(R.string.wallpaper_verification_idle)
            binding.wallpaperStatus.setText(R.string.wallpaper_boss_controls)
        } else if (!cfg.source_enabled) {
            binding.wallpaperStatus.setText(R.string.wallpaper_source_disabled)
        } else {
            binding.wallpaperVerificationStatus.setText(R.string.wallpaper_verification_idle)
            binding.wallpaperStatus.setText(R.string.wallpaper_ready)
        }

        refreshScenariosSummary()
        binding.wallpaperOpenLeverageButton.visibility =
            if (cfg.leverage_action_enabled) View.VISIBLE else View.GONE
    }

    private fun refreshScenariosSummary() {
        if (scenarios.isEmpty()) {
            binding.wallpaperScenariosSummary.setText(R.string.wallpaper_scenarios_empty)
            return
        }
        binding.wallpaperScenariosSummary.text = scenarios.joinToString("\n") { scenario ->
            val actionIds = scenario.actions.joinToString(", ") { it.possibility_id }
            "${scenario.event}: $actionIds"
        }
    }

    private fun toggleEnabled(enabled: Boolean) {
        lifecycleScope.launch {
            repository.updateConfig(WallpaperConfigUpdateRequest(enabled = enabled))
                .onSuccess { applyConfig(it) }
                .onFailure {
                    updatingUi = true
                    binding.wallpaperEnabledSwitch.isChecked = !enabled
                    updatingUi = false
                    Toast.makeText(this@WallpaperActivity, it.message, Toast.LENGTH_LONG).show()
                }
        }
    }

    private fun saveOptions() {
        val interval = binding.wallpaperIntervalInput.text.toString().toIntOrNull()
        if (interval == null || interval < 1) {
            Toast.makeText(this, R.string.wallpaper_invalid_interval, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            repository.updateConfig(
                WallpaperConfigUpdateRequest(
                    check_interval_minutes = interval,
                    dismiss_apps_before_capture = binding.wallpaperDismissAppsSwitch.isChecked,
                    scenarios = WallpaperScenariosWrapper(scenarios = scenarios)
                )
            ).onSuccess {
                applyConfig(it)
                Toast.makeText(this@WallpaperActivity, R.string.wallpaper_saved, Toast.LENGTH_SHORT).show()
            }.onFailure {
                Toast.makeText(this@WallpaperActivity, it.message, Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun addScenario() {
        val event = eventIds.getOrNull(binding.wallpaperScenarioEvent.selectedItemPosition) ?: return
        val actionId = actions.getOrNull(binding.wallpaperScenarioAction.selectedItemPosition)?.possibility_id
            ?: binding.wallpaperScenarioAction.selectedItem?.toString()
            ?: return
        val delay = binding.wallpaperScenarioDelay.text.toString().toIntOrNull() ?: 30
        val seconds = binding.wallpaperScenarioSeconds.text.toString().toIntOrNull() ?: 3600
        val config = mutableMapOf<String, Any?>()
        if (actionId.contains("add_time") || actionId.contains("lock")) {
            config["seconds"] = seconds
        }
        if (actionId.startsWith("leverage_photo")) {
            config["target_mode"] = "random"
        }
        val trigger = mutableMapOf<String, Any?>("delay_minutes" to delay)
        if (event == "mismatch") {
            trigger["mode"] = "strict"
        }
        if (event == "app_unreachable") {
            trigger["threshold_minutes"] = 120
        }
        scenarios.removeAll { it.event == event }
        scenarios.add(
            WallpaperScenarioDto(
                id = UUID.randomUUID().toString(),
                event = event,
                trigger = trigger,
                actions = listOf(WallpaperScenarioActionDto(possibility_id = actionId, config = config))
            )
        )
        refreshScenariosSummary()
        saveOptions()
    }

    private fun clearScenarios() {
        scenarios.clear()
        refreshScenariosSummary()
        saveOptions()
    }

    private fun startVerification() {
        val hours = durationHours.getOrNull(binding.wallpaperVerificationDuration.selectedItemPosition) ?: return
        lifecycleScope.launch {
            repository.startVerificationSession(hours)
                .onSuccess {
                    Toast.makeText(this@WallpaperActivity, R.string.wallpaper_verification_started, Toast.LENGTH_SHORT).show()
                    loadAll()
                }
                .onFailure {
                    Toast.makeText(this@WallpaperActivity, it.message, Toast.LENGTH_LONG).show()
                }
        }
    }

    private fun uploadWallpaper(file: File) {
        binding.wallpaperUploadButton.isEnabled = false
        binding.wallpaperStatus.setText(R.string.wallpaper_uploading)
        lifecycleScope.launch {
            repository.upload(file)
                .onSuccess {
                    Toast.makeText(this@WallpaperActivity, R.string.wallpaper_upload_success, Toast.LENGTH_SHORT).show()
                    WallpaperWorker.syncNow(this@WallpaperActivity, forceRefresh = true)
                    loadAll()
                }
                .onFailure {
                    Toast.makeText(this@WallpaperActivity, it.message, Toast.LENGTH_LONG).show()
                    binding.wallpaperUploadButton.isEnabled = true
                    binding.wallpaperStatus.setText(R.string.wallpaper_ready)
                }
        }
    }

    private fun copyToCache(uri: Uri): File? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val ext = contentResolver.getType(uri)?.let { type ->
                when {
                    type.contains("png") -> ".png"
                    type.contains("webp") -> ".webp"
                    else -> ".jpg"
                }
            } ?: ".jpg"
            val file = File(cacheDir, "wallpaper_${System.currentTimeMillis()}$ext")
            FileOutputStream(file).use { output -> inputStream.copyTo(output) }
            file
        } catch (_: Exception) {
            null
        }
    }

    private fun Boolean?.orFalse(): Boolean = this == true
}
