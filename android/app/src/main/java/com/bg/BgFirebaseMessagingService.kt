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
                val title = message.notification?.title ?: "OTB"
                val body = message.notification?.body ?: ""
                if (body.isNotEmpty()) {
                    NotificationHelper.showTeaser(applicationContext, title, body)
                }
            }
            "new_task" -> {
                val title = message.data["title"] ?: message.notification?.title ?: "OTB"
                val body = message.data["body"] ?: message.notification?.body ?: "Nouvelle tâche"
                val taskId = message.data["task_id"] ?: ""
                val triggerAlarm = message.data["trigger_alarm"] == "true"
                val alarmSound = message.data["alarm_sound"] ?: "urgent"
                NotificationHelper.showTaskNotification(applicationContext, title, body, taskId, triggerAlarm, alarmSound)
            }
            "proof_reviewed" -> {
                val title = message.notification?.title ?: "OTB"
                val body = message.notification?.body ?: ""
                val taskId = message.data["task_id"] ?: ""
                if (body.isNotEmpty()) {
                    NotificationHelper.showProofReviewedNotification(applicationContext, title, body, taskId)
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
