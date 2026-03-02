package com.bg

import android.util.Log
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
        }
    }

    override fun onNewToken(token: String) {
        Log.d(TAG, "FCM token refreshed")
        val prefs = getSharedPreferences(WallpaperWorker.PREFS_NAME, MODE_PRIVATE)
        val deviceId = prefs.getString(WallpaperWorker.KEY_DEVICE_ID, null)
        if (deviceId != null) {
            serviceScope.launch {
                DeviceRepository().updateFcmToken(deviceId, token)
            }
        }
    }

    companion object {
        private const val TAG = "BgFCM"
    }
}
