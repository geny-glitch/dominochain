package com.bg

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews
class ChasterWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        ChasterWidgetWorker.updateNow(context)
        ChasterWidgetWorker.enqueue(context)
    }

    override fun onEnabled(context: Context) {
        ChasterWidgetWorker.updateNow(context)
        ChasterWidgetWorker.enqueue(context)
    }

    companion object {
        fun updateFromLock(context: Context, lock: com.bg.api.ChasterLock?, error: String?) {
            val remainingSec = lock?.remaining_seconds ?: 0
            val useCountdown = lock != null && !lock.is_frozen && remainingSec > 0

            // Même logique que l'app : remaining_seconds pour éviter la dérive serveur/appareil
            val endTimeMs = if (useCountdown) {
                System.currentTimeMillis() + remainingSec * 1000L
            } else null
            val title = when {
                lock != null -> lock.title?.takeIf { it.isNotBlank() }
                else -> null
            }
            val staticText = when {
                lock != null && lock.is_frozen -> "Gelé"
                error != null -> "Non connecté"
                lock != null && (lock.remaining_seconds ?: 0) <= 0 -> "Terminé"
                lock == null -> "Aucun lock"
                else -> formatRemaining(lock.remaining_seconds ?: 0)
            }

            updateWidgets(context, title, staticText, endTimeMs)
        }

        private fun formatRemaining(sec: Int): String {
            if (sec <= 0) return "Terminé"
            val days = sec / 86400
            val hours = (sec % 86400) / 3600
            val mins = (sec % 3600) / 60
            val secs = sec % 60
            return when {
                days > 0 -> "${days}j ${hours}h ${mins}min ${secs}s"
                hours > 0 -> "${hours}h ${mins}min ${secs}s"
                mins > 0 -> "${mins}min ${secs}s"
                else -> "${secs}s"
            }
        }

        fun updateWidgets(
            context: Context,
            title: String?,
            remaining: String,
            endTimeMs: Long? = null
        ) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, ChasterWidgetProvider::class.java)
            )
            val pendingIntent = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.widget_chaster)

                if (endTimeMs != null) {
                    // Chronometer en mode compte à rebours — se met à jour automatiquement chaque seconde
                    val base = SystemClock.elapsedRealtime() + (endTimeMs - System.currentTimeMillis())
                    views.setViewVisibility(R.id.widget_chaster_chrono, android.view.View.VISIBLE)
                    views.setViewVisibility(R.id.widget_chaster_remaining, android.view.View.GONE)
                    views.setChronometer(R.id.widget_chaster_chrono, base, null, true)
                    views.setChronometerCountDown(R.id.widget_chaster_chrono, true)
                    views.setOnClickPendingIntent(R.id.widget_chaster_chrono, pendingIntent)
                } else {
                    views.setViewVisibility(R.id.widget_chaster_chrono, android.view.View.GONE)
                    views.setViewVisibility(R.id.widget_chaster_remaining, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.widget_chaster_remaining, remaining)
                    views.setOnClickPendingIntent(R.id.widget_chaster_remaining, pendingIntent)
                }

                if (!title.isNullOrBlank()) {
                    views.setViewVisibility(R.id.widget_chaster_title, android.view.View.VISIBLE)
                    views.setTextViewText(R.id.widget_chaster_title, title)
                } else {
                    views.setViewVisibility(R.id.widget_chaster_title, android.view.View.GONE)
                }
                views.setOnClickPendingIntent(R.id.widget_chaster_label, pendingIntent)
                views.setOnClickPendingIntent(R.id.widget_chaster_title, pendingIntent)

                appWidgetManager.updateAppWidget(id, views)
            }
        }
    }
}
