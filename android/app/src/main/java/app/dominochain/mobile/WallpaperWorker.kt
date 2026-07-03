package app.dominochain.mobile

import app.dominochain.mobile.api.RetrofitClient
import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL
import java.util.concurrent.TimeUnit

class WallpaperWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    enum class SyncResult {
        Success, NoWallpaper, MissingSession, Failed
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val forceRefresh = inputData.getBoolean(KEY_FORCE_REFRESH, false)
        when (performSync(applicationContext, forceRefresh = forceRefresh)) {
            SyncResult.Success -> Result.success()
            SyncResult.NoWallpaper -> Result.success()
            SyncResult.MissingSession -> Result.success()
            SyncResult.Failed -> Result.retry()
        }
    }

    companion object {
        private const val TAG = "WallpaperWorker"
        internal const val PREFS_NAME = "bg_prefs"
        internal const val KEY_DEVICE_ID = "device_id"
        private const val KEY_LAST_WALLPAPER_UPDATED_AT = "last_wallpaper_updated_at"
        private const val KEY_FORCE_REFRESH = "force_refresh"

        private const val POLL_INTERVAL_MINUTES = 1L

        suspend fun performSync(
            context: Context,
            forceRefresh: Boolean = false
        ): SyncResult = withContext(Dispatchers.IO) {
            try {
                val sessionManager = SessionManager(context)
                RetrofitClient.sessionManager = sessionManager
                val deviceId = sessionManager.deviceId
                val token = sessionManager.token

                if (deviceId.isNullOrBlank()) {
                    Log.w(TAG, "No deviceId in session, skipping wallpaper sync")
                    return@withContext SyncResult.MissingSession
                }
                if (token.isNullOrBlank()) {
                    Log.w(TAG, "No auth token in session, skipping wallpaper sync")
                    return@withContext SyncResult.MissingSession
                }

                val repository = DeviceRepository()
                val result = repository.getWallpaper(deviceId)
                if (result.isFailure) {
                    Log.e(TAG, "getWallpaper failed: ${result.exceptionOrNull()?.message}")
                    return@withContext SyncResult.Failed
                }
                val wallpaper = result.getOrNull() ?: run {
                    Log.d(TAG, "No wallpaper available (404)")
                    return@withContext SyncResult.NoWallpaper
                }

                val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val lastUpdated = prefs.getString(KEY_LAST_WALLPAPER_UPDATED_AT, null)
                val unchanged = lastUpdated == wallpaper.updated_at
                if (unchanged && !forceRefresh) {
                    Log.d(TAG, "Wallpaper unchanged (updated_at=$lastUpdated), skipping")
                    return@withContext SyncResult.Success
                }

                val bitmap = downloadImage(wallpaper.url)
                if (bitmap == null) {
                    Log.e(TAG, "Failed to download wallpaper from ${wallpaper.url}")
                    return@withContext SyncResult.Failed
                }
                val scaledBitmap = scaleBitmapForWallpaper(bitmap) ?: bitmap

                val wallpaperManager = WallpaperManager.getInstance(context)
                wallpaperManager.setBitmap(scaledBitmap)

                prefs.edit().putString(KEY_LAST_WALLPAPER_UPDATED_AT, wallpaper.updated_at).apply()
                Log.d(TAG, "Wallpaper set successfully (updated_at=${wallpaper.updated_at}, force=$forceRefresh)")

                SyncResult.Success
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set wallpaper", e)
                SyncResult.Failed
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

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<WallpaperWorker>(
                POLL_INTERVAL_MINUTES,
                TimeUnit.MINUTES
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "wallpaper_sync",
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        fun syncNow(context: Context, forceRefresh: Boolean = false) {
            val data = Data.Builder()
                .putBoolean(KEY_FORCE_REFRESH, forceRefresh)
                .build()
            val request = OneTimeWorkRequestBuilder<WallpaperWorker>()
                .setInputData(data)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "wallpaper_sync_now",
                ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
