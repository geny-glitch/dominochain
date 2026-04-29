package com.bg

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class CigaretteQuickAddWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_QUICK_ADD_CIGARETTE) {
            TrackerRepository(context).increment(TrackerType.Cigarettes)
            CigaretteTrackerWidgetProvider.updateWidgets(context)
            updateWidgets(context)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val ACTION_QUICK_ADD_CIGARETTE = "com.bg.action.QUICK_ADD_CIGARETTE"

        fun updateWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, CigaretteQuickAddWidgetProvider::class.java)
            )
            val snapshot = TrackerRepository(context).snapshot(TrackerType.Cigarettes)
            ids.forEach { appWidgetId ->
                appWidgetManager.updateAppWidget(appWidgetId, remoteViews(context, snapshot))
            }
        }

        private fun remoteViews(context: Context, snapshot: TrackerSnapshot): RemoteViews {
            val addIntent = PendingIntent.getBroadcast(
                context,
                21,
                Intent(context, CigaretteQuickAddWidgetProvider::class.java).apply {
                    action = ACTION_QUICK_ADD_CIGARETTE
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            return RemoteViews(context.packageName, R.layout.widget_cigarette_quick_add).apply {
                setTextViewText(
                    R.id.widget_cigarette_quick_add_count,
                    context.getString(R.string.tracker_cigarettes_quick_add_count, snapshot.count)
                )
                setOnClickPendingIntent(R.id.widget_cigarette_quick_add_root, addIntent)
                setOnClickPendingIntent(R.id.widget_cigarette_quick_add_button, addIntent)
            }
        }
    }
}
