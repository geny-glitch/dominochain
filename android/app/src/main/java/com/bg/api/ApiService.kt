package com.bg.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

data class RegisterRequest(
    val device_id: String,
    val screen_width: Int? = null,
    val screen_height: Int? = null
)

data class RegisterResponse(
    val id: Long,
    val device_id: String,
    val web_url: String
)

data class WallpaperResponse(
    val url: String,
    val updated_at: String
)

interface ApiService {
    @POST("api/devices")
    suspend fun register(@Body request: RegisterRequest): Response<RegisterResponse>

    @GET("api/devices/{deviceId}/wallpaper")
    suspend fun getWallpaper(@Path("deviceId") deviceId: String): Response<WallpaperResponse>
}
