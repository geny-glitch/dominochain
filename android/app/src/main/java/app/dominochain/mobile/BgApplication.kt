package app.dominochain.mobile

import android.app.Application
import androidx.appcompat.app.AppCompatDelegate
import io.sentry.android.core.SentryAndroid

class BgApplication : Application() {
    val sessionManager by lazy { SessionManager(this) }

    override fun onCreate() {
        super.onCreate()
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES)
        if (BuildConfig.SENTRY_DSN.isNotEmpty()) {
            SentryAndroid.init(this) { options ->
                options.dsn = BuildConfig.SENTRY_DSN
                options.isSendDefaultPii = true
            }
        }
    }
}
