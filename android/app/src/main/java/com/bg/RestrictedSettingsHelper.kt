package com.bg

import android.app.AppOpsManager
import android.app.ecm.EnhancedConfirmationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings

object RestrictedSettingsHelper {

    private const val SETTING_ACCESSIBILITY = AppOpsManager.OPSTR_BIND_ACCESSIBILITY_SERVICE

    fun isAccessibilityRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        return try {
            context.getSystemService(EnhancedConfirmationManager::class.java)
                .isRestricted(context.packageName, SETTING_ACCESSIBILITY)
        } catch (_: Exception) {
            false
        }
    }

    fun createAccessibilitySetupIntent(context: Context): Intent {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                val ecm = context.getSystemService(EnhancedConfirmationManager::class.java)
                val packageName = context.packageName
                if (ecm.isRestricted(packageName, SETTING_ACCESSIBILITY)) {
                    return ecm.createRestrictedSettingDialogIntent(packageName, SETTING_ACCESSIBILITY)
                        .addNewTaskFlags()
                }
            } catch (_: PackageManager.NameNotFoundException) {
            } catch (_: Exception) {
            }
        }
        return Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addNewTaskFlags()
    }

    fun openAccessibilitySetup(context: Context): Boolean {
        val intents = listOf(
            createAccessibilitySetupIntent(context),
            createAppDetailsIntent(context),
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addNewTaskFlags()
        ).distinctBy { it.action to it.dataString }

        for (intent in intents) {
            try {
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    private fun createAppDetailsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
        }.addNewTaskFlags()

    private fun Intent.addNewTaskFlags(): Intent = apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
