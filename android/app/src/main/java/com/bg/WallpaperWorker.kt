package com.bg

import android.app.WallpaperManager
import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL

class WallpaperWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val deviceId = prefs.getString(KEY_DEVICE_ID, null) ?: return@withContext Result.success()

            val repository = DeviceRepository()
            val result = repository.getWallpaper(deviceId)
            val wallpaper = result.getOrNull() ?: return@withContext Result.success()

            val lastUpdated = prefs.getString(KEY_LAST_WALLPAPER_UPDATED_AT, null)
            if (lastUpdated == wallpaper.updated_at) return@withContext Result.success()

            val bitmap = downloadImage(wallpaper.url) ?: return@withContext Result.retry()

            val wallpaperManager = WallpaperManager.getInstance(applicationContext)
            wallpaperManager.setBitmap(bitmap)

            prefs.edit().putString(KEY_LAST_WALLPAPER_UPDATED_AT, wallpaper.updated_at).apply()

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set wallpaper", e)
            Result.retry()
        }
    }

    private fun downloadImage(urlString: String): android.graphics.Bitmap? {
        return try {
            val url = URL(urlString)
            val connection = url.openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            connection.doInput = true
            connection.connect()

            val inputStream = connection.inputStream
            val bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream.close()
            connection.disconnect()
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Failed to download image", e)
            null
        }
    }

    companion object {
        private const val TAG = "WallpaperWorker"
        private const val PREFS_NAME = "bg_prefs"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_LAST_WALLPAPER_UPDATED_AT = "last_wallpaper_updated_at"

        private const val POLL_INTERVAL_MINUTES = 5L

        fun schedule(context: Context) {
            val request = androidx.work.PeriodicWorkRequestBuilder<WallpaperWorker>(
                java.util.concurrent.TimeUnit.MINUTES,
                POLL_INTERVAL_MINUTES
            ).build()
            androidx.work.WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "wallpaper_sync",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
