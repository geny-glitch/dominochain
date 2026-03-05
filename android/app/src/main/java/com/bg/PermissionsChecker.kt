package com.bg

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.PermissionChecker
import androidx.core.content.PermissionChecker.PERMISSION_GRANTED

object PermissionsChecker {

    data class Result(
        val allOk: Boolean,
        val accessibilityEnabled: Boolean,
        val batteryOptimizationIgnored: Boolean,
        val notificationsGranted: Boolean,
        val missingReasons: List<String>
    )

    fun check(context: Context): Result {
        val accessibilityEnabled = BgAccessibilityService.isEnabled(context)
        val batteryOptimizationIgnored = isBatteryOptimizationIgnored(context)
        val notificationsGranted = areNotificationsGranted(context)

        val missingReasons = mutableListOf<String>()
        if (!accessibilityEnabled) missingReasons.add("accessibilité")
        if (!batteryOptimizationIgnored) missingReasons.add("optimisation batterie")
        if (!notificationsGranted) missingReasons.add("notifications")

        return Result(
            allOk = missingReasons.isEmpty(),
            accessibilityEnabled = accessibilityEnabled,
            batteryOptimizationIgnored = batteryOptimizationIgnored,
            notificationsGranted = notificationsGranted,
            missingReasons = missingReasons
        )
    }

    private fun isBatteryOptimizationIgnored(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun areNotificationsGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return PermissionChecker.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) == PERMISSION_GRANTED
    }
}
