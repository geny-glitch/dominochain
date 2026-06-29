package com.bg

import android.content.Context
import android.util.Log
import com.bg.api.RetrofitClient

object WallpaperSampleUploader {
    private const val TAG = "WallpaperSampleUpload"

    suspend fun readAndUpload(context: Context): Boolean {
        val app = context.applicationContext as? BgApplication ?: run {
            Log.e(TAG, "BgApplication not available")
            return false
        }
        RetrofitClient.sessionManager = app.sessionManager
        val deviceId = app.sessionManager.deviceId
        if (deviceId.isNullOrBlank()) {
            Log.e(TAG, "Upload failed: deviceId is null")
            return false
        }
        if (app.sessionManager.token.isNullOrBlank()) {
            Log.e(TAG, "Upload failed: token is null")
            return false
        }

        val file = WallpaperReader.readHomeWallpaper(context) ?: return false
        return try {
            val result = DeviceRepository().uploadWallpaperSample(deviceId, file)
            result.fold(
                onSuccess = {
                    Log.d(TAG, "Wallpaper sample upload success")
                    true
                },
                onFailure = { e ->
                    Log.e(TAG, "Wallpaper sample upload failed: ${e.message}", e)
                    false
                }
            )
        } finally {
            file.delete()
        }
    }
}
