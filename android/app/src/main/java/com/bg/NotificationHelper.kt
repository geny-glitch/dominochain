package com.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat

object NotificationHelper {
    const val CHANNEL_ID_DEFAULT = "otb_default"
    private const val CHANNEL_ID = "otb_teaser"
    private const val CHANNEL_TASKS = "otb_tasks"
    private const val CHANNEL_TASKS_URGENT = "otb_tasks_urgent"
    private const val TEASER_NOTIFICATION_ID = 2001
    private const val TASK_NOTIFICATION_ID_BASE = 3000
    private const val PROOF_REVIEWED_NOTIFICATION_ID = 3100
    private const val SCREENSHOT_REQUEST_NOTIFICATION_ID = 3200
    private const val PERMISSIONS_MISSING_NOTIFICATION_ID = 3300
    private const val PUNISHMENT_NOTIFICATION_ID_BASE = 3400
    private const val APP_UPDATE_NOTIFICATION_ID = 3500

    fun showAppUpdateNotification(context: Context, title: String, body: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, BuildConfig.NOTIFICATION_TITLE, NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, SettingsActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(SettingsActivity.EXTRA_OPEN_UPDATE, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            APP_UPDATE_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()

        notificationManager.notify(APP_UPDATE_NOTIFICATION_ID, notification)
    }

    /** Shown periodically when permissions are missing (accessibility, battery, notifications). */
    fun showPermissionsMissingNotification(context: Context, missingReasons: List<String>) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, BuildConfig.NOTIFICATION_TITLE, NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            PERMISSIONS_MISSING_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val reasons = missingReasons.joinToString(", ")
        val contentText = "Accorde les autorisations : $reasons"

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(BuildConfig.NOTIFICATION_TITLE)
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()

        notificationManager.notify(PERMISSIONS_MISSING_NOTIFICATION_ID, notification)
    }

    /** Shown when the boss requests a screenshot but the accessibility service is not running. */
    @Suppress("UNUSED_PARAMETER")
    fun showScreenshotRequestNotification(context: Context, title: String, body: String, serviceEnabled: Boolean = false) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, BuildConfig.NOTIFICATION_TITLE, NotificationManager.IMPORTANCE_HIGH)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = RestrictedSettingsHelper.createAccessibilitySetupIntent(context).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            SCREENSHOT_REQUEST_NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (serviceEnabled) {
            "Le service Bg ne répond plus. Désactive puis réactive Bg dans Accessibilité pour réactiver les captures."
        } else {
            "Active l'accessibilité Bg pour permettre les captures d'écran"
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()

        notificationManager.notify(SCREENSHOT_REQUEST_NOTIFICATION_ID, notification)
    }

    fun showTeaser(context: Context, title: String, body: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, BuildConfig.NOTIFICATION_TITLE, NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(TEASER_NOTIFICATION_ID, notification)
    }

    fun showTaskNotification(context: Context, title: String, body: String, taskId: String, triggerAlarm: Boolean, alarmSound: String = "urgent") {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = if (triggerAlarm) CHANNEL_TASKS_URGENT else CHANNEL_TASKS

        val soundUri: Uri? = when {
            !triggerAlarm -> null
            alarmSound == "default" -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            else -> Uri.parse("android.resource://${context.packageName}/${R.raw.urgent_alarm}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channelName = if (triggerAlarm) "${BuildConfig.NOTIFICATION_TITLE} Tâches urgentes" else "${BuildConfig.NOTIFICATION_TITLE} Tâches"
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                enableVibration(true)
                if (triggerAlarm && soundUri != null) {
                    setSound(
                        soundUri,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                }
            }
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("task_id", taskId)
            putExtra("open_tasks", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            taskId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(if (triggerAlarm) NotificationCompat.CATEGORY_ALARM else NotificationCompat.CATEGORY_REMINDER)

        if (triggerAlarm && soundUri != null) {
            builder.setSound(soundUri).setDefaults(NotificationCompat.DEFAULT_ALL)
        }

        notificationManager.notify(TASK_NOTIFICATION_ID_BASE + taskId.hashCode().and(0x7F), builder.build())
    }

    fun showProofReviewedNotification(context: Context, title: String, body: String, taskId: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_TASKS, "${BuildConfig.NOTIFICATION_TITLE} Tâches", NotificationManager.IMPORTANCE_DEFAULT)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("task_id", taskId)
            putExtra("open_tasks", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            (PROOF_REVIEWED_NOTIFICATION_ID + taskId.hashCode()).and(0x7FFF),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_TASKS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        notificationManager.notify(PROOF_REVIEWED_NOTIFICATION_ID, notification)
    }

    fun showPunishmentNotification(context: Context, title: String, body: String, taskId: String) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_TASKS, "${BuildConfig.NOTIFICATION_TITLE} Tâches", NotificationManager.IMPORTANCE_HIGH)
            notificationManager.createNotificationChannel(channel)
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("task_id", taskId)
            putExtra("open_tasks", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            (PUNISHMENT_NOTIFICATION_ID_BASE + taskId.hashCode()).and(0x7FFF),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_TASKS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()

        notificationManager.notify((PUNISHMENT_NOTIFICATION_ID_BASE + taskId.hashCode()).and(0x7FFF), notification)
    }
}
