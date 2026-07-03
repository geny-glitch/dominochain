package app.dominochain.mobile.api

import app.dominochain.mobile.BuildConfig
import app.dominochain.mobile.SessionManager
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object RetrofitClient {
    var sessionManager: SessionManager? = null

    private val authInterceptor = Interceptor { chain ->
        val token = sessionManager?.token
        val deviceId = sessionManager?.deviceId
        val request = chain.request()
        val newBuilder = request.newBuilder()
        if (!token.isNullOrBlank()) {
            newBuilder.addHeader("Authorization", "Bearer $token")
        }
        if (!deviceId.isNullOrBlank()) {
            newBuilder.addHeader("X-Device-Id", deviceId)
        }
        chain.proceed(newBuilder.build())
    }

    private val okHttpClient = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL.ensureTrailingSlash())
        .client(okHttpClient)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    val api: ApiService = retrofit.create(ApiService::class.java)
}

private fun String.ensureTrailingSlash(): String {
    return if (endsWith("/")) this else "$this/"
}
