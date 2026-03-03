package com.bg

import android.app.Application

class BgApplication : Application() {
    val sessionManager by lazy { SessionManager(this) }
}
