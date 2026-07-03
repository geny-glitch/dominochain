package app.dominochain.mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED
import androidx.core.content.PermissionChecker.checkSelfPermission
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivitySettingsBinding
import kotlinx.coroutines.launch
import android.Manifest
import androidx.lifecycle.lifecycleScope

class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()
    private val authRepository = AuthRepository()

    private val requestNotificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
        refreshPermissionsStatus()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = getString(R.string.settings)

        val deviceId = sessionManager.deviceId ?: return
        binding.debugDeviceId.text = deviceId
        binding.debugServerUrl.text = app.dominochain.mobile.BuildConfig.API_BASE_URL
        binding.buildNumber.text = getString(R.string.build_number, app.dominochain.mobile.BuildConfig.VERSION_CODE)
        binding.checkUpdatesButton.setOnClickListener {
            AppUpdateManager(this).checkForUpdates(force = true)
        }
        binding.accountNickname.text = sessionManager.nickname ?: "-"
        binding.accountDeviceName.setText(getDeviceName() ?: "")

        setupPermissions()
        setupAccount()
        setupShowcaseVitrine()
        fetchBossStatus()

        if (intent.getBooleanExtra(EXTRA_OPEN_UPDATE, false)) {
            AppUpdateManager(this).checkForUpdates(force = true)
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissionsStatus()
        fetchBossStatus()
    }

    private var showcaseListenerQuiet = false
    private var lastLoadedQuizSecondsPerPoint = 1
    private var lastLoadedSnakeSecondsPerFruit = 300
    private var lastLoadedDinoSecondsPerObstacle = 300
    private var lastLoadedTetrisSecondsPerLine = 60

    private fun setupShowcaseVitrine() {
        binding.showcaseQuizSwitch.setOnCheckedChangeListener { view, checked ->
            if (showcaseListenerQuiet) return@setOnCheckedChangeListener
            if (!checked && !binding.showcaseSnakeSwitch.isChecked && !binding.showcaseDinoSwitch.isChecked && !binding.showcaseTetrisSwitch.isChecked && !binding.showcaseBackdoorSwitch.isChecked) {
                showcaseListenerQuiet = true
                view.isChecked = true
                showcaseListenerQuiet = false
                Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                return@setOnCheckedChangeListener
            }
            saveShowcaseSettings()
        }
        binding.showcaseSnakeSwitch.setOnCheckedChangeListener { view, checked ->
            if (showcaseListenerQuiet) return@setOnCheckedChangeListener
            if (!checked && !binding.showcaseQuizSwitch.isChecked && !binding.showcaseDinoSwitch.isChecked && !binding.showcaseTetrisSwitch.isChecked && !binding.showcaseBackdoorSwitch.isChecked) {
                showcaseListenerQuiet = true
                view.isChecked = true
                showcaseListenerQuiet = false
                Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                return@setOnCheckedChangeListener
            }
            saveShowcaseSettings()
        }
        binding.showcaseDinoSwitch.setOnCheckedChangeListener { view, checked ->
            if (showcaseListenerQuiet) return@setOnCheckedChangeListener
            if (!checked && !binding.showcaseQuizSwitch.isChecked && !binding.showcaseSnakeSwitch.isChecked && !binding.showcaseTetrisSwitch.isChecked && !binding.showcaseBackdoorSwitch.isChecked) {
                showcaseListenerQuiet = true
                view.isChecked = true
                showcaseListenerQuiet = false
                Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                return@setOnCheckedChangeListener
            }
            saveShowcaseSettings()
        }
        binding.showcaseTetrisSwitch.setOnCheckedChangeListener { view, checked ->
            if (showcaseListenerQuiet) return@setOnCheckedChangeListener
            if (!checked && !binding.showcaseQuizSwitch.isChecked && !binding.showcaseSnakeSwitch.isChecked && !binding.showcaseDinoSwitch.isChecked && !binding.showcaseBackdoorSwitch.isChecked) {
                showcaseListenerQuiet = true
                view.isChecked = true
                showcaseListenerQuiet = false
                Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                return@setOnCheckedChangeListener
            }
            saveShowcaseSettings()
        }
        binding.showcaseBackdoorSwitch.setOnCheckedChangeListener { view, checked ->
            if (showcaseListenerQuiet) return@setOnCheckedChangeListener
            if (!checked && !binding.showcaseQuizSwitch.isChecked && !binding.showcaseSnakeSwitch.isChecked && !binding.showcaseDinoSwitch.isChecked && !binding.showcaseTetrisSwitch.isChecked) {
                showcaseListenerQuiet = true
                view.isChecked = true
                showcaseListenerQuiet = false
                Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                return@setOnCheckedChangeListener
            }
            saveShowcaseSettings()
        }
        binding.showcaseQuizSecondsSave.setOnClickListener {
            saveShowcaseSecondsInputs()
        }
        binding.showcaseSnakeSecondsSave.setOnClickListener {
            saveShowcaseSecondsInputs()
        }
        binding.showcaseDinoSecondsSave.setOnClickListener {
            saveShowcaseSecondsInputs()
        }
        binding.showcaseTetrisSecondsSave.setOnClickListener {
            saveShowcaseSecondsInputs()
        }
    }

    private fun saveShowcaseSecondsInputs() {
        val quizSeconds = binding.showcaseQuizSecondsInput.text.toString().trim().toIntOrNull()
        val snakeSeconds = binding.showcaseSnakeSecondsInput.text.toString().trim().toIntOrNull()
        val dinoSeconds = binding.showcaseDinoSecondsInput.text.toString().trim().toIntOrNull()
        val tetrisSeconds = binding.showcaseTetrisSecondsInput.text.toString().trim().toIntOrNull()
        if (quizSeconds == null || quizSeconds <= 0 || snakeSeconds == null || snakeSeconds <= 0 || dinoSeconds == null || dinoSeconds <= 0 || tetrisSeconds == null || tetrisSeconds <= 0) {
            Toast.makeText(this, R.string.showcase_seconds_invalid, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            val q = binding.showcaseQuizSwitch.isChecked
            val s = binding.showcaseSnakeSwitch.isChecked
            val d = binding.showcaseDinoSwitch.isChecked
            val t = binding.showcaseTetrisSwitch.isChecked
            val b = binding.showcaseBackdoorSwitch.isChecked
            authRepository.updateShowcaseSettings(q, s, d, t, b, quizSeconds, snakeSeconds, dinoSeconds, tetrisSeconds)
                .onSuccess {
                    Toast.makeText(this@SettingsActivity, R.string.showcase_seconds_saved, Toast.LENGTH_SHORT).show()
                    loadShowcaseSettings()
                }
                .onFailure { err ->
                    Toast.makeText(
                        this@SettingsActivity,
                        err.message ?: getString(R.string.showcase_settings_error),
                        Toast.LENGTH_SHORT
                    ).show()
                    loadShowcaseSettings()
                }
        }
    }

    private fun loadShowcaseSettings() {
        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            authRepository.getShowcaseSettings()
                .onSuccess { st ->
                    showcaseListenerQuiet = true
                    binding.showcaseQuizSwitch.isChecked = st.showcase_quiz_enabled
                    binding.showcaseSnakeSwitch.isChecked = st.showcase_snake_enabled
                    binding.showcaseDinoSwitch.isChecked = st.showcase_dino_enabled ?: true
                    binding.showcaseTetrisSwitch.isChecked = st.showcase_tetris_enabled ?: true
                    binding.showcaseBackdoorSwitch.isChecked = st.showcase_backdoor_enabled
                    val quizSec = st.showcase_quiz_seconds_per_point?.takeIf { it > 0 } ?: 1
                    val snakeSec = st.showcase_snake_seconds_per_fruit?.takeIf { it > 0 } ?: 300
                    val dinoSec = st.showcase_dino_seconds_per_obstacle?.takeIf { it > 0 } ?: 300
                    val tetrisSec = st.showcase_tetris_seconds_per_line?.takeIf { it > 0 } ?: 60
                    lastLoadedQuizSecondsPerPoint = quizSec
                    lastLoadedSnakeSecondsPerFruit = snakeSec
                    lastLoadedDinoSecondsPerObstacle = dinoSec
                    lastLoadedTetrisSecondsPerLine = tetrisSec
                    binding.showcaseQuizSecondsInput.setText(quizSec.toString())
                    binding.showcaseSnakeSecondsInput.setText(snakeSec.toString())
                    binding.showcaseDinoSecondsInput.setText(dinoSec.toString())
                    binding.showcaseTetrisSecondsInput.setText(tetrisSec.toString())
                    showcaseListenerQuiet = false
                }
        }
    }

    private fun saveShowcaseSettings() {
        val q = binding.showcaseQuizSwitch.isChecked
        val s = binding.showcaseSnakeSwitch.isChecked
        val d = binding.showcaseDinoSwitch.isChecked
        val t = binding.showcaseTetrisSwitch.isChecked
        val b = binding.showcaseBackdoorSwitch.isChecked
        val rawQuiz = binding.showcaseQuizSecondsInput.text.toString().trim()
        val quizSec = rawQuiz.toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedQuizSecondsPerPoint
        val rawSnake = binding.showcaseSnakeSecondsInput.text.toString().trim()
        val snakeSec = rawSnake.toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedSnakeSecondsPerFruit
        val rawDino = binding.showcaseDinoSecondsInput.text.toString().trim()
        val dinoSec = rawDino.toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedDinoSecondsPerObstacle
        val rawTetris = binding.showcaseTetrisSecondsInput.text.toString().trim()
        val tetrisSec = rawTetris.toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedTetrisSecondsPerLine
        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            authRepository.updateShowcaseSettings(q, s, d, t, b, quizSec, snakeSec, dinoSec, tetrisSec)
                .onFailure { err ->
                    Toast.makeText(
                        this@SettingsActivity,
                        err.message ?: getString(R.string.showcase_settings_error),
                        Toast.LENGTH_SHORT
                    ).show()
                    loadShowcaseSettings()
                }
        }
    }

    private fun fetchBossStatus() {
        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            authRepository.getMe()
                .onSuccess { me ->
                    if (me.boss_nickname != null) {
                        binding.bossRequestSection.visibility = android.view.View.GONE
                        binding.bossOwnedSection.visibility = android.view.View.VISIBLE
                        binding.bossNameText.text = me.boss_nickname
                    } else {
                        binding.bossRequestSection.visibility = android.view.View.VISIBLE
                        binding.bossOwnedSection.visibility = android.view.View.GONE
                    }
                    val isBeta = me.role == null || me.role == "beta"
                    if (isBeta) {
                        binding.showcaseControlSection.visibility = View.VISIBLE
                        loadShowcaseSettings()
                    } else {
                        binding.showcaseControlSection.visibility = View.GONE
                    }
                }
                .onFailure {
                    binding.bossRequestSection.visibility = android.view.View.VISIBLE
                    binding.bossOwnedSection.visibility = android.view.View.GONE
                    binding.showcaseControlSection.visibility = View.GONE
                }
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun setupPermissions() {
        binding.permissionAccessibilityAction.setOnClickListener {
            if (!RestrictedSettingsHelper.openAccessibilitySetup(this)) {
                Toast.makeText(this, R.string.settings_open_failed, Toast.LENGTH_SHORT).show()
            }
        }
        binding.permissionBatteryAction.setOnClickListener {
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
        binding.permissionNotificationsAction.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun refreshPermissionsStatus() {
        val result = PermissionsChecker.check(this)
        binding.permissionAccessibilityStatus.text = if (result.accessibilityEnabled)
            getString(R.string.permission_granted) else getString(R.string.permission_missing)
        binding.permissionBatteryStatus.text = if (result.batteryOptimizationIgnored)
            getString(R.string.permission_granted) else getString(R.string.permission_missing)
        binding.permissionNotificationsStatus.text = if (result.notificationsGranted)
            getString(R.string.permission_granted) else getString(R.string.permission_missing)

        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            repository.reportPermissionsStatus(
                sessionManager.deviceId!!,
                result.allOk,
                result.missingReasons
            )
        }
    }

    private fun setupAccount() {
        binding.changePasswordButton.setOnClickListener {
            val current = binding.currentPassword.text.toString()
            val newPass = binding.newPassword.text.toString()
            val confirm = binding.confirmPassword.text.toString()
            if (current.isBlank()) {
                Toast.makeText(this, "Mot de passe actuel requis", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (newPass.length < 6) {
                Toast.makeText(this, "6 caractères minimum", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (newPass != confirm) {
                Toast.makeText(this, "Les mots de passe ne correspondent pas", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            lifecycleScope.launch {
                authRepository.changePassword(current, newPass, confirm)
                    .onSuccess {
                        Toast.makeText(this@SettingsActivity, "Mot de passe modifié", Toast.LENGTH_SHORT).show()
                        binding.currentPassword.text?.clear()
                        binding.newPassword.text?.clear()
                        binding.confirmPassword.text?.clear()
                    }
                    .onFailure {
                        Toast.makeText(this@SettingsActivity, it.message ?: "Erreur", Toast.LENGTH_SHORT).show()
                    }
            }
        }

        binding.accountDeviceName.setOnFocusChangeListener { _, hasFocus ->
            if (!hasFocus) saveDeviceName()
        }

        binding.sendControlRequestButton.setOnClickListener {
            val bossNickname = binding.bossNicknameInput.text.toString().trim()
            if (bossNickname.isBlank()) {
                Toast.makeText(this, "Entrez le pseudo du boss", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            lifecycleScope.launch {
                authRepository.sendControlRequest(bossNickname)
                    .onSuccess { msg ->
                        Toast.makeText(this@SettingsActivity, msg, Toast.LENGTH_SHORT).show()
                    }
                    .onFailure {
                        Toast.makeText(this@SettingsActivity, it.message ?: "Erreur", Toast.LENGTH_SHORT).show()
                    }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        saveDeviceName()
    }

    private fun getDeviceName(): String? {
        return         getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_DEVICE_NAME, null)?.takeIf { it.isNotBlank() }
    }

    private fun saveDeviceName() {
        val name = binding.accountDeviceName.text.toString().trim().takeIf { it.isNotEmpty() }
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_DEVICE_NAME, name ?: "").apply()
        val deviceId = sessionManager.deviceId ?: return
        lifecycleScope.launch {
            repository.updateName(deviceId, name).onSuccess { }
        }
    }

    companion object {
        const val EXTRA_OPEN_UPDATE = "open_update"
        private const val PREFS_NAME = "bg_prefs"
        private const val KEY_DEVICE_NAME = "device_name"
    }
}
