package app.dominochain.mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivitySettingsBinding
import kotlinx.coroutines.launch

class SettingsActivity : BetaShellActivity() {

    private lateinit var binding: ActivitySettingsBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = DeviceRepository()
    private val authRepository = AuthRepository()

    override val navDestination = AppNavDestination.ACCOUNT

    private val requestNotificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { _ ->
        refreshPermissionsStatus()
    }

    override fun onCreateContent(container: FrameLayout) {
        binding = ActivitySettingsBinding.inflate(layoutInflater, container, true)

        val deviceId = sessionManager.deviceId ?: return
        binding.debugDeviceId.text = deviceId
        binding.debugServerUrl.text = BuildConfig.API_BASE_URL
        binding.buildNumber.text = getString(R.string.build_number, BuildConfig.VERSION_CODE)
        binding.checkUpdatesButton.setOnClickListener {
            AppUpdateManager(this).checkForUpdates(force = true)
        }
        binding.accountNickname.text = sessionManager.nickname ?: getString(R.string.empty_placeholder)
        binding.accountDeviceName.setText(getDeviceName() ?: "")

        setupPermissions()
        setupAccount()
        fetchBossStatus()

        if (intent.getBooleanExtra(EXTRA_OPEN_UPDATE, false)) {
            AppUpdateManager(this).checkForUpdates(force = true)
        }
    }

    override fun onResume() {
        super.onResume()
        if (::binding.isInitialized) {
            refreshPermissionsStatus()
            fetchBossStatus()
        }
    }

    override fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) {
        if (!::binding.isInitialized) return
        if (!config.sectionVisible("control")) {
            binding.bossRequestSection.visibility = View.GONE
            binding.bossOwnedSection.visibility = View.GONE
        }
    }

    private fun fetchBossStatus() {
        lifecycleScope.launch {
            RetrofitClient.sessionManager = sessionManager
            val meResult = authRepository.getMe()
            val settings = authRepository.getShowcaseSettings().getOrNull()
            val sectionsConfig = AppSectionsConfig.from(settings)

            meResult
                .onSuccess { me ->
                    if (!sectionsConfig.sectionVisible("control")) {
                        binding.bossRequestSection.visibility = View.GONE
                        binding.bossOwnedSection.visibility = View.GONE
                    } else if (me.boss_nickname != null) {
                        binding.bossRequestSection.visibility = View.GONE
                        binding.bossOwnedSection.visibility = View.VISIBLE
                        binding.bossNameText.text = me.boss_nickname
                    } else {
                        binding.bossRequestSection.visibility = View.VISIBLE
                        binding.bossOwnedSection.visibility = View.GONE
                    }
                }
                .onFailure {
                    binding.bossRequestSection.visibility = View.VISIBLE
                    binding.bossOwnedSection.visibility = View.GONE
                    if (!sectionsConfig.sectionVisible("control")) {
                        binding.bossRequestSection.visibility = View.GONE
                    }
                }
        }
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
                        Toast.makeText(this, R.string.settings_battery_open_failed, Toast.LENGTH_SHORT).show()
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
                Toast.makeText(this, R.string.password_current_required, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (newPass.length < 6) {
                Toast.makeText(this, R.string.password_min_length, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            if (newPass != confirm) {
                Toast.makeText(this, R.string.auth_passwords_mismatch, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            lifecycleScope.launch {
                authRepository.changePassword(current, newPass, confirm)
                    .onSuccess {
                        Toast.makeText(this@SettingsActivity, R.string.password_changed, Toast.LENGTH_SHORT).show()
                        binding.currentPassword.text?.clear()
                        binding.newPassword.text?.clear()
                        binding.confirmPassword.text?.clear()
                    }
                    .onFailure {
                        Toast.makeText(
                            this@SettingsActivity,
                            it.message ?: getString(R.string.generic_error),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
            }
        }

        binding.accountDeviceName.setOnFocusChangeListener { _, hasFocus ->
            if (!hasFocus) saveDeviceName()
        }

        binding.sendControlRequestButton.setOnClickListener {
            val bossNickname = binding.bossNicknameInput.text.toString().trim()
            if (bossNickname.isBlank()) {
                Toast.makeText(this, R.string.boss_nickname_required, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            lifecycleScope.launch {
                authRepository.sendControlRequest(bossNickname)
                    .onSuccess { msg ->
                        Toast.makeText(this@SettingsActivity, msg, Toast.LENGTH_SHORT).show()
                    }
                    .onFailure {
                        Toast.makeText(
                            this@SettingsActivity,
                            it.message ?: getString(R.string.generic_error),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
            }
        }

        binding.logoutButton.setOnClickListener {
            sessionManager.clear()
            RetrofitClient.sessionManager = sessionManager
            startActivity(
                Intent(this, LoginActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                }
            )
            finish()
        }
    }

    override fun onPause() {
        super.onPause()
        if (::binding.isInitialized) saveDeviceName()
    }

    private fun getDeviceName(): String? {
        return getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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
