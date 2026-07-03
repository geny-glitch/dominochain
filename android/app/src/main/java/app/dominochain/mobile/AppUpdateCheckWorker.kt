package app.dominochain.mobile

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

class AppUpdateCheckWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val lastCheck = prefs.getLong(KEY_LAST_CHECK_MS, 0L)
            if (System.currentTimeMillis() - lastCheck < COOLDOWN_MS) {
                return@withContext Result.success()
            }
            prefs.edit().putLong(KEY_LAST_CHECK_MS, System.currentTimeMillis()).apply()

            val (update, error) = AppUpdateChecker.fetchUpdateInfo()
            if (update == null) {
                Log.w(TAG, "Background update check failed: $error")
                return@withContext Result.success()
            }
            if (AppUpdateChecker.isUpdateAvailable(update)) {
                AppUpdateChecker.notifyUpdateAvailable(applicationContext, update)
            }
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "App update check worker failed", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "AppUpdateCheckWorker"
        private const val PREFS_NAME = "bg_update_prefs"
        private const val KEY_LAST_CHECK_MS = "last_update_check_ms"
        private const val COOLDOWN_MS = 60 * 60 * 1000L
        private const val CHECK_INTERVAL_HOURS = 6L

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<AppUpdateCheckWorker>(
                CHECK_INTERVAL_HOURS,
                TimeUnit.HOURS
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "app_update_check",
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }
}
