package com.bg

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.bg.api.RetrofitClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WallpaperVerifyWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val sessionManager = SessionManager(applicationContext)
            RetrofitClient.sessionManager = sessionManager
            val deviceId = sessionManager.deviceId
            val token = sessionManager.token

            if (deviceId.isNullOrBlank()) {
                Log.w(TAG, "No deviceId in session, skipping wallpaper verify")
                return@withContext Result.success()
            }
            if (token.isNullOrBlank()) {
                Log.w(TAG, "No auth token in session, skipping wallpaper verify")
                return@withContext Result.success()
            }

            val uploaded = WallpaperSampleUploader.uploadCachedWallpaper(applicationContext)
                || WallpaperSampleUploader.readAndUpload(applicationContext)
            if (uploaded) {
                Log.d(TAG, "Wallpaper sample uploaded from verify worker")
                Result.success()
            } else {
                Log.w(TAG, "Failed to read or upload wallpaper sample from verify worker")
                Result.retry()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Wallpaper verify worker failed", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "WallpaperVerifyWorker"
        private const val WORK_NAME = "wallpaper_verify_now"

        fun verifyNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<WallpaperVerifyWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
