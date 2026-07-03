package app.dominochain.mobile

import android.content.Context
import android.content.SharedPreferences

class SessionManager(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    var token: String?
        get() = prefs.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }
        set(value) = prefs.edit().putString(KEY_TOKEN, value ?: "").apply()

    var deviceId: String?
        get() = prefs.getString(KEY_DEVICE_ID, null)?.takeIf { it.isNotBlank() }
        set(value) = prefs.edit().putString(KEY_DEVICE_ID, value ?: "").apply()

    var nickname: String?
        get() = prefs.getString(KEY_NICKNAME, null)?.takeIf { it.isNotBlank() }
        set(value) = prefs.edit().putString(KEY_NICKNAME, value ?: "").apply()

    val isLoggedIn: Boolean
        get() = token != null && deviceId != null

    fun clear() {
        prefs.edit()
            .remove(KEY_TOKEN)
            .remove(KEY_NICKNAME)
            .apply()
    }

    companion object {
        const val PREFS_NAME = "bg_prefs"
        const val KEY_TOKEN = "auth_token"
        const val KEY_DEVICE_ID = "device_id"
        const val KEY_NICKNAME = "nickname"
    }
}
