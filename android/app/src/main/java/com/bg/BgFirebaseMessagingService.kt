package com.bg

import android.util.Log
import com.bg.api.RetrofitClient
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class BgFirebaseMessagingService : FirebaseMessagingService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(message: RemoteMessage) {
        when (message.data["type"]) {
            "new_wallpaper" -> {
                Log.d(TAG, "New wallpaper push received, syncing...")
                WallpaperWorker.syncNow(applicationContext)
            }
            "teaser" -> {
                val title = message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.notification?.body ?: ""
                if (body.isNotEmpty()) {
                    NotificationHelper.showTeaser(applicationContext, title, body)
                }
            }
            "new_task" -> {
                val title = message.data["title"] ?: message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.data["body"] ?: message.notification?.body ?: "Nouvelle tâche"
                val taskId = message.data["task_id"] ?: ""
                val triggerAlarm = message.data["trigger_alarm"] == "true"
                val alarmSound = message.data["alarm_sound"] ?: "urgent"
                NotificationHelper.showTaskNotification(applicationContext, title, body, taskId, triggerAlarm, alarmSound)
            }
            "proof_reviewed" -> {
                val title = message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.notification?.body ?: ""
                val taskId = message.data["task_id"] ?: ""
                if (body.isNotEmpty()) {
                    NotificationHelper.showProofReviewedNotification(applicationContext, title, body, taskId)
                }
            }
            "showcase_game_started" -> {
                val title = message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.notification?.body ?: ""
                if (body.isNotEmpty()) {
                    NotificationHelper.showTeaser(applicationContext, title, body)
                }
            }
            "punishment" -> {
                val title = message.data["title"] ?: message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.data["body"] ?: message.notification?.body ?: "Tâche non terminée à temps..."
                val taskId = message.data["task_id"] ?: ""
                NotificationHelper.showPunishmentNotification(applicationContext, title, body, taskId)
            }
            "verify_wallpaper" -> {
                Log.d(TAG, "Verify wallpaper push received")
                val title = message.data["title"] ?: message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.data["body"] ?: message.notification?.body ?: "On vérifie ton fond d'écran"
                NotificationHelper.showTeaser(applicationContext, title, body)
                WallpaperVerifyWorker.verifyNow(applicationContext)
            }
            "take_screenshot" -> {
                Log.d(TAG, "Take screenshot push received")
                val title = message.data["title"] ?: message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val body = message.data["body"] ?: message.notification?.body ?: "On vérifie ton écran"
                if (BgAccessibilityService.requestCapture()) {
                    NotificationHelper.showTeaser(applicationContext, title, body)
                } else {
                    val serviceEnabled = BgAccessibilityService.isEnabled(applicationContext)
                    Log.w(TAG, "Accessibility service not running (enabled=$serviceEnabled) - notifying user")
                    NotificationHelper.showScreenshotRequestNotification(applicationContext, title, body, serviceEnabled)
                }
            }
            "grant_permissions" -> {
                Log.d(TAG, "Grant permissions push received")
                val title = message.data["title"] ?: message.notification?.title ?: BuildConfig.NOTIFICATION_TITLE
                val result = PermissionsChecker.check(applicationContext)
                serviceScope.launch {
                    val app = applicationContext as? BgApplication ?: return@launch
                    val deviceId = app.sessionManager.deviceId
                    val token = app.sessionManager.token
                    if (!deviceId.isNullOrBlank() && !token.isNullOrBlank()) {
                        RetrofitClient.sessionManager = app.sessionManager
                        DeviceRepository().reportPermissionsStatus(deviceId, result.allOk, result.missingReasons)
                    }
                }
                if (result.allOk) {
                    NotificationHelper.showTeaser(applicationContext, title, "Tout est déjà configuré ✓")
                } else {
                    NotificationHelper.showPermissionsMissingNotification(applicationContext, result.missingReasons)
                }
            }
        }
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token refreshed")
        val app = applicationContext as? BgApplication ?: return
        RetrofitClient.sessionManager = app.sessionManager
        val deviceId = app.sessionManager.deviceId ?: return
        if (app.sessionManager.token != null) {
            serviceScope.launch {
                DeviceRepository().updateFcmToken(deviceId, token)
            }
        }
    }

    companion object {
        private const val TAG = "BgFCM"
    }
}
