package app.dominochain.mobile

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

class PermissionsWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val app = applicationContext as? BgApplication ?: return@withContext Result.success()
            val sessionManager = app.sessionManager
            val deviceId = sessionManager.deviceId
            val token = sessionManager.token

            if (deviceId.isNullOrBlank() || token.isNullOrBlank()) {
                Log.d(TAG, "No deviceId or token, skipping permissions check")
                return@withContext Result.success()
            }

            val result = PermissionsChecker.check(applicationContext)

            app.dominochain.mobile.api.RetrofitClient.sessionManager = sessionManager
            val repository = DeviceRepository()
            repository.reportPermissionsStatus(deviceId, result.allOk, result.missingReasons)

            if (!result.allOk) {
                NotificationHelper.showPermissionsMissingNotification(
                    applicationContext,
                    result.missingReasons
                )
            }

            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Permissions check failed", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "PermissionsWorker"
        private const val CHECK_INTERVAL_HOURS = 6L

        fun schedule(context: Context) {
            val request = androidx.work.PeriodicWorkRequestBuilder<PermissionsWorker>(
                CHECK_INTERVAL_HOURS,
                TimeUnit.HOURS
            ).build()
            androidx.work.WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "permissions_check",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        fun checkNow(context: Context) {
            val request = androidx.work.OneTimeWorkRequestBuilder<PermissionsWorker>().build()
            androidx.work.WorkManager.getInstance(context).enqueueUniqueWork(
                "permissions_check_now",
                androidx.work.ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
