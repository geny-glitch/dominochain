package com.bg

import android.content.Context
import android.util.Log
import com.bg.api.RetrofitClient
import java.io.File

object WallpaperSampleUploader {
    private const val TAG = "WallpaperSampleUpload"

    suspend fun readAndUpload(context: Context): Boolean {
        val file = WallpaperReader.readHomeWallpaper(context) ?: run {
            Log.e(TAG, "Upload failed: could not read wallpaper sample")
            return false
        }
        return uploadFile(context, file, deleteAfterUpload = true)
    }

    suspend fun uploadCachedWallpaper(context: Context): Boolean {
        val cacheFile = WallpaperReader.cachedWallpaperFile(context)
        if (!cacheFile.exists() || cacheFile.length() <= 0L) {
            Log.w(TAG, "Upload failed: no cached wallpaper file")
            return false
        }
        val tempFile = File(context.cacheDir, "wallpaper_sample_${System.currentTimeMillis()}.jpg")
        return try {
            cacheFile.inputStream().use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            uploadFile(context, tempFile, deleteAfterUpload = true)
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed: could not copy cached wallpaper", e)
            false
        }
    }

    private suspend fun uploadFile(context: Context, file: File, deleteAfterUpload: Boolean): Boolean {
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
            if (deleteAfterUpload) {
                file.delete()
            }
        }
    }
}
