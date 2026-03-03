package com.bg

import android.app.Application
import com.bg.api.RetrofitClient
import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL
import java.util.concurrent.TimeUnit

class WallpaperWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val app = applicationContext as? BgApplication ?: return@withContext Result.success()
            RetrofitClient.sessionManager = app.sessionManager
            val deviceId = app.sessionManager.deviceId ?: return@withContext Result.success()
            if (app.sessionManager.token == null) return@withContext Result.success()

            val repository = DeviceRepository()
            val result = repository.getWallpaper(deviceId)
            val wallpaper = result.getOrNull() ?: return@withContext Result.success()

            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastUpdated = prefs.getString(KEY_LAST_WALLPAPER_UPDATED_AT, null)
            if (lastUpdated == wallpaper.updated_at) return@withContext Result.success()

            val bitmap = downloadImage(wallpaper.url) ?: return@withContext Result.retry()
            val scaledBitmap = scaleBitmapForWallpaper(bitmap) ?: bitmap

            val wallpaperManager = WallpaperManager.getInstance(applicationContext)
            wallpaperManager.setBitmap(scaledBitmap)

            prefs.edit().putString(KEY_LAST_WALLPAPER_UPDATED_AT, wallpaper.updated_at).apply()

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set wallpaper", e)
            Result.retry()
        }
    }

    private fun scaleBitmapForWallpaper(bitmap: Bitmap): Bitmap? {
        return try {
            val maxSize = 2048
            val width = bitmap.width
            val height = bitmap.height
            if (width <= maxSize && height <= maxSize) return bitmap
            val scale = maxSize.toFloat() / maxOf(width, height)
            val newWidth = (width * scale).toInt()
            val newHeight = (height * scale).toInt()
            Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to scale bitmap", e)
            null
        }
    }

    private fun downloadImage(urlString: String): Bitmap? {
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
        internal const val PREFS_NAME = "bg_prefs"
        internal const val KEY_DEVICE_ID = "device_id"
        private const val KEY_LAST_WALLPAPER_UPDATED_AT = "last_wallpaper_updated_at"

        private const val POLL_INTERVAL_MINUTES = 1L

        fun schedule(context: Context) {
            val request = androidx.work.PeriodicWorkRequestBuilder<WallpaperWorker>(
                POLL_INTERVAL_MINUTES,
                TimeUnit.MINUTES
            ).build()
            androidx.work.WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "wallpaper_sync",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        fun syncNow(context: Context) {
            val request = androidx.work.OneTimeWorkRequestBuilder<WallpaperWorker>().build()
            androidx.work.WorkManager.getInstance(context).enqueueUniqueWork(
                "wallpaper_sync_now",
                androidx.work.ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
