package com.bg

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.annotation.DimenRes

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

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        onWidgetSizeChanged(context, appWidgetManager, appWidgetId)
    }

    private data class WidgetState(
        val remaining: String,
        val endTimeMs: Long?,
        val pishockEnabled: Boolean,
        val quizSecondsPerPoint: Int?,
        val snakeSecondsPerFruit: Int?,
        val dinoSecondsPerObstacle: Int?
    )

    companion object {
        private const val PREFS_NAME = "chaster_widget_state"
        private const val KEY_INIT = "initialized"
        private const val KEY_STATIC = "static_text"
        private const val KEY_END = "end_time_ms"
        private const val KEY_PISH = "pishock"
        private const val KEY_QUIZ = "quiz_seconds"
        private const val KEY_SNAKE = "snake_seconds"
        private const val KEY_DINO = "dino_seconds"

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        private fun persistState(context: Context, state: WidgetState) {
            prefs(context).edit()
                .putBoolean(KEY_INIT, true)
                .putString(KEY_STATIC, state.remaining)
                .putLong(KEY_END, state.endTimeMs ?: 0L)
                .putBoolean(KEY_PISH, state.pishockEnabled)
                .putInt(KEY_QUIZ, state.quizSecondsPerPoint ?: -1)
                .putInt(KEY_SNAKE, state.snakeSecondsPerFruit ?: -1)
                .putInt(KEY_DINO, state.dinoSecondsPerObstacle ?: -1)
                .apply()
        }

        private fun loadState(context: Context): WidgetState? {
            val p = prefs(context)
            if (!p.getBoolean(KEY_INIT, false)) return null
            val end = p.getLong(KEY_END, 0L).takeIf { it > 0L }
            val quizRaw = p.getInt(KEY_QUIZ, -1)
            val snakeRaw = p.getInt(KEY_SNAKE, -1)
            val dinoRaw = p.getInt(KEY_DINO, -1)
            return WidgetState(
                remaining = p.getString(KEY_STATIC, "--") ?: "--",
                endTimeMs = end,
                pishockEnabled = p.getBoolean(KEY_PISH, false),
                quizSecondsPerPoint = quizRaw.takeIf { it > 0 },
                snakeSecondsPerFruit = snakeRaw.takeIf { it > 0 },
                dinoSecondsPerObstacle = dinoRaw.takeIf { it > 0 }
            )
        }

        private fun pxToDp(context: Context, @DimenRes dimen: Int): Float {
            return context.resources.getDimension(dimen) / context.resources.displayMetrics.density
        }

        private fun iconSlotDp(context: Context, pishock: Boolean): Float {
            if (!pishock) return 0f
            return (
                context.resources.getDimension(R.dimen.ds_widget_icon_sm) +
                    context.resources.getDimension(R.dimen.ds_space_xs)
                ) / context.resources.displayMetrics.density
        }

        private fun widgetSizeDp(options: Bundle): Pair<Int, Int> {
            val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val maxW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
            val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            val w = when {
                maxW > 0 -> maxW
                minW > 0 -> minW
                else -> 110
            }
            val h = when {
                maxH > 0 -> maxH
                minH > 0 -> minH
                else -> 40
            }
            return w to h
        }

        private fun textSizeSpForWidget(
            context: Context,
            widthDp: Int,
            heightDp: Int,
            pishock: Boolean,
            approximateCharCount: Int,
            reserveBottomDp: Float
        ): Float {
            val pad = 2f * pxToDp(context, R.dimen.ds_space_sm)
            val icon = iconSlotDp(context, pishock)
            val usableW = (widthDp - pad - icon).coerceAtLeast(24f)
            val usableH = (heightDp - pad - reserveBottomDp).coerceAtLeast(16f)
            val fromH = usableH * 0.58f
            val chars = approximateCharCount.coerceIn(3, 18)
            val fromW = usableW * 0.92f / chars
            return minOf(fromH, fromW).coerceIn(11f, 56f)
        }

        fun updateFromLock(
            context: Context,
            lock: com.bg.api.ChasterLock?,
            error: String?,
            pishockEnabled: Boolean,
            quizSecondsPerPoint: Int?,
            snakeSecondsPerFruit: Int?,
            dinoSecondsPerObstacle: Int?
        ) {
            val remainingSec = lock?.remaining_seconds ?: 0
            val useCountdown = lock != null && !lock.is_frozen && remainingSec > 0

            val endTimeMs = if (useCountdown) {
                System.currentTimeMillis() + remainingSec * 1000L
            } else null
            val staticText = when {
                lock != null && lock.is_frozen -> "Gelé"
                error != null -> "Non connecté"
                lock != null && (lock.remaining_seconds ?: 0) <= 0 -> "Terminé"
                lock == null -> "Aucun lock"
                else -> formatRemaining(lock.remaining_seconds ?: 0)
            }

            updateWidgets(
                context,
                staticText,
                endTimeMs,
                pishockEnabled,
                quizSecondsPerPoint,
                snakeSecondsPerFruit,
                dinoSecondsPerObstacle
            )
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
            remaining: String,
            endTimeMs: Long? = null,
            pishockEnabled: Boolean = false,
            quizSecondsPerPoint: Int? = null,
            snakeSecondsPerFruit: Int? = null,
            dinoSecondsPerObstacle: Int? = null
        ) {
            val state = WidgetState(
                remaining,
                endTimeMs,
                pishockEnabled,
                quizSecondsPerPoint,
                snakeSecondsPerFruit,
                dinoSecondsPerObstacle
            )
            persistState(context, state)
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, ChasterWidgetProvider::class.java)
            )
            ids.forEach { applyWidget(context, appWidgetManager, it, state) }
        }

        internal fun onWidgetSizeChanged(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val state = loadState(context) ?: return
            applyWidget(context, appWidgetManager, appWidgetId, state)
        }

        private fun applyWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            state: WidgetState
        ) {
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val (wDp, hDp) = widgetSizeDp(options)
            val quiz = state.quizSecondsPerPoint?.takeIf { it > 0 }
            val snake = state.snakeSecondsPerFruit?.takeIf { it > 0 }
            val dino = state.dinoSecondsPerObstacle?.takeIf { it > 0 }
            val reserveBottom = if (quiz != null || snake != null || dino != null) 16f else 0f
            val charCount = if (state.endTimeMs != null) {
                10
            } else {
                state.remaining.length.coerceAtLeast(4)
            }
            val textSp = textSizeSpForWidget(
                context,
                wDp,
                hDp,
                state.pishockEnabled,
                charCount,
                reserveBottom
            )

            val pendingIntent = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val views = RemoteViews(context.packageName, R.layout.widget_chaster)

            views.setTextViewTextSize(
                R.id.widget_chaster_chrono,
                TypedValue.COMPLEX_UNIT_SP,
                textSp
            )
            views.setTextViewTextSize(
                R.id.widget_chaster_remaining,
                TypedValue.COMPLEX_UNIT_SP,
                textSp
            )

            if (state.endTimeMs != null) {
                val base = SystemClock.elapsedRealtime() +
                    (state.endTimeMs - System.currentTimeMillis())
                views.setViewVisibility(R.id.widget_chaster_chrono, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_chaster_remaining, android.view.View.GONE)
                views.setChronometer(R.id.widget_chaster_chrono, base, null, true)
                views.setChronometerCountDown(R.id.widget_chaster_chrono, true)
            } else {
                views.setViewVisibility(R.id.widget_chaster_chrono, android.view.View.GONE)
                views.setViewVisibility(R.id.widget_chaster_remaining, android.view.View.VISIBLE)
                views.setTextViewText(R.id.widget_chaster_remaining, state.remaining)
            }

            if (state.pishockEnabled) {
                views.setViewVisibility(R.id.widget_pishock_icon, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_pishock_icon, android.view.View.GONE)
            }

            val gameSecondsText = listOfNotNull(
                quiz?.let { "Q: $it" },
                snake?.let { "S: $it" },
                dino?.let { "D: $it" }
            ).joinToString("  ")
            if (gameSecondsText.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_chaster_snake_hint, android.view.View.VISIBLE)
                views.setTextViewText(R.id.widget_chaster_snake_hint, gameSecondsText)
            } else {
                views.setViewVisibility(R.id.widget_chaster_snake_hint, android.view.View.GONE)
            }

            views.setOnClickPendingIntent(R.id.widget_chaster_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
