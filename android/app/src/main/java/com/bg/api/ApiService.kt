package com.bg.api

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Path

data class RegisterRequest(
    val device_id: String,
    val screen_width: Int? = null,
    val screen_height: Int? = null,
    val fcm_token: String? = null,
    val name: String? = null
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

data class FcmTokenRequest(val fcm_token: String)

data class NameRequest(val name: String?)

interface ApiService {
    @POST("api/devices")
    suspend fun register(@Body request: RegisterRequest): Response<RegisterResponse>

    @PATCH("api/devices/{deviceId}/fcm_token")
    suspend fun updateFcmToken(
        @Path("deviceId") deviceId: String,
        @Body body: FcmTokenRequest
    ): Response<Unit>

    @PATCH("api/devices/{deviceId}/name")
    suspend fun updateName(
        @Path("deviceId") deviceId: String,
        @Body body: NameRequest
    ): Response<Unit>

    @GET("api/devices/{deviceId}/wallpaper")
    suspend fun getWallpaper(@Path("deviceId") deviceId: String): Response<WallpaperResponse>
}
