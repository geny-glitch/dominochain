package app.dominochain.mobile

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import java.io.File

class AppUpdateManager(private val activity: AppCompatActivity) {

    private val prefs by lazy {
        activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    fun checkForUpdates(force: Boolean = false) {
        if (!force) {
            val lastCheck = prefs.getLong(KEY_LAST_CHECK_MS, 0L)
            if (System.currentTimeMillis() - lastCheck < COOLDOWN_MS) return
        }
        Thread {
            prefs.edit().putLong(KEY_LAST_CHECK_MS, System.currentTimeMillis()).apply()
            val (update, error) = AppUpdateChecker.fetchUpdateInfo()
            activity.runOnUiThread {
                if (activity.isFinishing) return@runOnUiThread
                if (update == null) {
                    if (force) Toast.makeText(activity, error ?: activity.getString(R.string.update_check_failed), Toast.LENGTH_LONG).show()
                    return@runOnUiThread
                }
                if (AppUpdateChecker.isUpdateAvailable(update)) {
                    AppUpdateChecker.markNotified(activity, update.versionCode)
                    showUpdateDialog(update)
                } else if (force) {
                    Toast.makeText(activity, R.string.update_up_to_date, Toast.LENGTH_SHORT).show()
                }
            }
        }.start()
    }

    private fun showUpdateDialog(update: AppUpdateChecker.UpdateInfo) {
        AlertDialog.Builder(activity)
            .setTitle(R.string.update_available_title)
            .setMessage(activity.getString(R.string.update_available_message))
            .setPositiveButton(R.string.update_download) { _, _ ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !activity.packageManager.canRequestPackageInstalls()
                ) {
                    openInstallPermissionSettings()
                } else {
                    downloadUpdate(update.url)
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun openInstallPermissionSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        activity.startActivity(intent)
        Toast.makeText(activity, R.string.update_install_permission_required, Toast.LENGTH_LONG).show()
    }

    private fun downloadUpdate(apkUrl: String) {
        val apkFile = File(activity.externalCacheDir ?: activity.cacheDir, APK_FILE_NAME)
        if (apkFile.exists()) {
            apkFile.delete()
        }

        val request = DownloadManager.Request(Uri.parse(apkUrl))
            .setTitle(activity.getString(R.string.update_download_title))
            .setDescription(activity.getString(R.string.update_download_description))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setDestinationUri(Uri.fromFile(apkFile))

        val downloadManager = activity.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = downloadManager.enqueue(request)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L) != downloadId) return
                context.unregisterReceiver(this)
                installDownloadedApk(downloadManager, downloadId)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE), Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE))
        }

        Toast.makeText(activity, R.string.update_download_started, Toast.LENGTH_SHORT).show()
    }

    private fun installDownloadedApk(downloadManager: DownloadManager, downloadId: Long) {
        val query = DownloadManager.Query().setFilterById(downloadId)
        downloadManager.query(query)?.use { cursor ->
            if (!cursor.moveToFirst()) return
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status != DownloadManager.STATUS_SUCCESSFUL) {
                Toast.makeText(activity, R.string.update_download_failed, Toast.LENGTH_LONG).show()
                return
            }
            installApk(File(activity.externalCacheDir ?: activity.cacheDir, APK_FILE_NAME))
        }
    }

    private fun installApk(apkFile: File) {
        val apkUri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            apkFile
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }

    private companion object {
        private const val APK_FILE_NAME = "app.apk"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PREFS_NAME = "bg_update_prefs"
        private const val KEY_LAST_CHECK_MS = "last_update_check_ms"
        private const val COOLDOWN_MS = 60 * 60 * 1000L
    }
}
