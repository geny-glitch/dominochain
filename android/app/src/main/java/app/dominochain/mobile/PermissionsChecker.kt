package app.dominochain.mobile

import android.Manifest
import android.content.Context
import android.os.Build
import android.os.PowerManager
import androidx.core.content.PermissionChecker
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED

object PermissionsChecker {

    data class Result(
        val allOk: Boolean,
        val accessibilityEnabled: Boolean,
        val batteryOptimizationIgnored: Boolean,
        val notificationsGranted: Boolean,
        val cameraGranted: Boolean,
        val missingReasons: List<String>
    )

    fun check(context: Context): Result {
        val accessibilityEnabled = BgAccessibilityService.isEnabled(context)
        val batteryOptimizationIgnored = isBatteryOptimizationIgnored(context)
        val notificationsGranted = areNotificationsGranted(context)
        val cameraGranted = isCameraGranted(context)

        val missingReasons = mutableListOf<String>()
        if (!accessibilityEnabled) missingReasons.add("accessibilité")
        if (!batteryOptimizationIgnored) missingReasons.add("optimisation batterie")
        if (!notificationsGranted) missingReasons.add("notifications")

        return Result(
            allOk = missingReasons.isEmpty(),
            accessibilityEnabled = accessibilityEnabled,
            batteryOptimizationIgnored = batteryOptimizationIgnored,
            notificationsGranted = notificationsGranted,
            cameraGranted = cameraGranted,
            missingReasons = missingReasons
        )
    }

    fun isCameraGranted(context: Context): Boolean {
        return PermissionChecker.checkSelfPermission(context, Manifest.permission.CAMERA) == PERMISSION_GRANTED
    }

    private fun isBatteryOptimizationIgnored(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun areNotificationsGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return PermissionChecker.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PERMISSION_GRANTED
    }
}
