package app.dominochain.mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

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
            val pendingResult = goAsync()
            incrementAndRefresh(context.applicationContext) {
                pendingResult.finish()
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val ACTION_QUICK_ADD_CIGARETTE = "app.dominochain.mobile.action.QUICK_ADD_CIGARETTE"
        private val widgetScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        private fun incrementAndRefresh(context: Context, onFinished: (() -> Unit)? = null) {
            val appContext = context.applicationContext
            val repository = TrackerRepository(appContext)
            widgetScope.launch {
                try {
                    if (SessionManager(appContext).isLoggedIn) {
                        repository.incrementRemote()
                    } else {
                        repository.increment(TrackerType.Cigarettes)
                    }
                    CigaretteTrackerWidgetProvider.updateWidgets(appContext)
                    updateWidgets(appContext)
                } finally {
                    onFinished?.invoke()
                }
            }
        }

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
