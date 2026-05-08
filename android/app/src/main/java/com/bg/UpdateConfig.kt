package com.bg

object UpdateConfig {
    val VERSION_JSON_URL: String
        get() = "${BuildConfig.API_BASE_URL.trimEnd('/')}/android/version"
}
