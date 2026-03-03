package com.bg

import android.app.Application
import io.sentry.android.core.SentryAndroid

class BgApplication : Application() {
    val sessionManager by lazy { SessionManager(this) }

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.SENTRY_DSN.isNotEmpty()) {
            SentryAndroid.init(this) { options ->
                options.dsn = BuildConfig.SENTRY_DSN
                options.isSendDefaultPii = true
            }
        }
    }
}
