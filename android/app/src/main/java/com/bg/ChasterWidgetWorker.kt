package com.bg

import android.content.Context
import com.bg.api.RetrofitClient
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

class ChasterWidgetWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val sessionManager = SessionManager(applicationContext)
        if (!sessionManager.isLoggedIn) {
            ChasterWidgetProvider.updateWidgets(applicationContext, null, "Non connecté")
            return@withContext Result.success()
        }

        RetrofitClient.sessionManager = sessionManager
        val repository = DeviceRepository()
        val result = repository.getChasterLock()

        result.fold(
            onSuccess = { response ->
                ChasterWidgetProvider.updateFromLock(
                    applicationContext,
                    response?.lock,
                    response?.error
                )
            },
            onFailure = {
                ChasterWidgetProvider.updateWidgets(applicationContext, null, "--")
            }
        )
        Result.success()
    }

    companion object {
        private const val WORK_NAME = "chaster_widget_update"

        fun enqueue(context: Context) {
            val request = PeriodicWorkRequestBuilder<ChasterWidgetWorker>(15, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }

        fun updateNow(context: Context) {
            WorkManager.getInstance(context).enqueue(
                androidx.work.OneTimeWorkRequest.from(ChasterWidgetWorker::class.java)
            )
        }
    }
}
