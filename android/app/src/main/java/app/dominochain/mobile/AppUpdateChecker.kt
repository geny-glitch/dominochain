package app.dominochain.mobile

import android.content.Context
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

object AppUpdateChecker {
    data class UpdateInfo(
        val versionCode: Int,
        val url: String
    )

    fun fetchUpdateInfo(): Pair<UpdateInfo?, String?> {
        val connection = (URL(UpdateConfig.VERSION_JSON_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = HTTP_TIMEOUT_MS
            readTimeout = HTTP_TIMEOUT_MS
            requestMethod = "GET"
        }

        return try {
            val code = connection.responseCode
            if (code !in 200..299) return Pair(null, "HTTP $code — ${UpdateConfig.VERSION_JSON_URL}")
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            Pair(UpdateInfo(versionCode = json.getInt("versionCode"), url = json.getString("url")), null)
        } catch (e: Exception) {
            Pair(null, e.message ?: e.javaClass.simpleName)
        } finally {
            connection.disconnect()
        }
    }

    fun isUpdateAvailable(update: UpdateInfo): Boolean {
        return update.versionCode > BuildConfig.VERSION_CODE
    }

    fun shouldNotify(context: Context, versionCode: Int): Boolean {
        if (versionCode <= BuildConfig.VERSION_CODE) return false
        val lastNotified = prefs(context).getInt(KEY_LAST_NOTIFIED_VERSION, 0)
        return versionCode > lastNotified
    }

    fun markNotified(context: Context, versionCode: Int) {
        prefs(context).edit().putInt(KEY_LAST_NOTIFIED_VERSION, versionCode).apply()
    }

    fun notifyUpdateAvailable(context: Context, update: UpdateInfo) {
        if (!shouldNotify(context, update.versionCode)) return
        markNotified(context, update.versionCode)
        NotificationHelper.showAppUpdateNotification(
            context,
            context.getString(R.string.update_available_title),
            context.getString(R.string.update_available_message)
        )
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private const val PREFS_NAME = "bg_update_prefs"
    private const val KEY_LAST_NOTIFIED_VERSION = "last_notified_version_code"
    private const val HTTP_TIMEOUT_MS = 10_000
}
