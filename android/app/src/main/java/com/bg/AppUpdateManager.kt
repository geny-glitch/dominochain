package com.bg

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
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

class AppUpdateManager(private val activity: AppCompatActivity) {

    fun checkForUpdates() {
        Thread {
            val update = fetchUpdateInfo() ?: return@Thread
            activity.runOnUiThread {
                if (update.versionCode > BuildConfig.VERSION_CODE && !activity.isFinishing) {
                    showUpdateDialog(update)
                }
            }
        }.start()
    }

    private fun showUpdateDialog(update: UpdateInfo) {
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

    private fun fetchUpdateInfo(): UpdateInfo? {
        val connection = (URL(UpdateConfig.VERSION_JSON_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = HTTP_TIMEOUT_MS
            readTimeout = HTTP_TIMEOUT_MS
            requestMethod = "GET"
        }

        return try {
            if (connection.responseCode !in 200..299) return null
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            UpdateInfo(
                versionCode = json.getInt("versionCode"),
                url = json.getString("url")
            )
        } catch (_: Exception) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private data class UpdateInfo(
        val versionCode: Int,
        val url: String
    )

    private companion object {
        private const val APK_FILE_NAME = "app.apk"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val HTTP_TIMEOUT_MS = 10_000
    }
}
