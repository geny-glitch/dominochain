package com.bg

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

object RestrictedSettingsHelper {

    fun isAccessibilityRestricted(context: Context): Boolean = false

    fun createAccessibilitySetupIntent(context: Context): Intent =
        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addNewTaskFlags()

    fun openAccessibilitySetup(context: Context): Boolean {
        val intents = listOf(
            createAccessibilitySetupIntent(context),
            createAppDetailsIntent(context),
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
