package com.bg

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class CigaretteTrackerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_INCREMENT_CIGARETTES) {
            TrackerRepository(context).increment(TrackerType.Cigarettes)
            updateWidgets(context)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val ACTION_INCREMENT_CIGARETTES = "com.bg.action.INCREMENT_CIGARETTES"

        fun updateWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, CigaretteTrackerWidgetProvider::class.java)
            )
            val snapshot = TrackerRepository(context).snapshot(TrackerType.Cigarettes)
            ids.forEach { appWidgetId ->
                appWidgetManager.updateAppWidget(appWidgetId, remoteViews(context, snapshot))
            }
        }

        private fun remoteViews(context: Context, snapshot: TrackerSnapshot): RemoteViews {
            val openAppIntent = PendingIntent.getActivity(
                context,
                10,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val incrementIntent = PendingIntent.getBroadcast(
                context,
                11,
                Intent(context, CigaretteTrackerWidgetProvider::class.java).apply {
                    action = ACTION_INCREMENT_CIGARETTES
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            return RemoteViews(context.packageName, R.layout.widget_tracker_cigarettes).apply {
                setTextViewText(R.id.widget_cigarettes_count, snapshot.count.toString())
                setTextViewText(R.id.widget_cigarettes_unit, snapshot.type.unitLabel)
                setOnClickPendingIntent(R.id.widget_cigarettes_root, openAppIntent)
                setOnClickPendingIntent(R.id.widget_cigarettes_increment, incrementIntent)
            }
        }
    }
}
