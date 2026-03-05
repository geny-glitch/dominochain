package com.bg.api

import okhttp3.MultipartBody
import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Multipart
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.Part
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
    val token: String?,
    val web_url: String
)

data class LoginRequest(
    val nickname: String,
    val password: String,
    val device_id: String,
    val screen_width: Int? = null,
    val screen_height: Int? = null,
    val fcm_token: String? = null,
    val name: String? = null
)

data class RegisterAuthRequest(
    val nickname: String,
    val password: String,
    val password_confirmation: String,
    val device_id: String,
    val screen_width: Int? = null,
    val screen_height: Int? = null,
    val fcm_token: String? = null,
    val name: String? = null
)

data class AuthResponse(
    val token: String?,
    val user: UserInfo,
    val device_id: String?,
    val web_url: String?
)

data class UserInfo(val nickname: String)

data class ChangePasswordRequest(
    val current_password: String,
    val password: String,
    val password_confirmation: String
)

data class WallpaperResponse(
    val url: String,
    val updated_at: String
)

data class FcmTokenRequest(val fcm_token: String)

data class NameRequest(val name: String?)
data class PermissionsRequest(val permissions_ok: Boolean, val permissions_missing: List<String>? = null)

interface ApiService {
    @POST("api/auth/login")
    suspend fun login(@Body request: LoginRequest): Response<AuthResponse>

    @POST("api/auth/register")
    suspend fun registerAuth(@Body request: RegisterAuthRequest): Response<AuthResponse>

    @PATCH("api/auth/password")
    suspend fun changePassword(@Body request: ChangePasswordRequest): Response<Unit>

    @POST("api/devices")
    suspend fun register(@Body request: RegisterRequest): Response<RegisterResponse>

    @POST("api/control_requests")
    suspend fun sendControlRequest(@Body body: ControlRequestBody): Response<ControlRequestResponse>

    data class ControlRequestBody(val boss_nickname: String)
    data class ControlRequestResponse(val message: String?)

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

    @PATCH("api/devices/{deviceId}/permissions")
    suspend fun updatePermissions(
        @Path("deviceId") deviceId: String,
        @Body body: PermissionsRequest
    ): Response<Unit>

    @GET("api/devices/{deviceId}/wallpaper")
    suspend fun getWallpaper(@Path("deviceId") deviceId: String): Response<WallpaperResponse>

    @GET("api/devices/{deviceId}/tasks")
    suspend fun getTasks(@Path("deviceId") deviceId: String): Response<List<TaskResponse>>

    @GET("api/devices/{deviceId}/tasks/{taskId}")
    suspend fun getTaskDetail(@Path("deviceId") deviceId: String, @Path("taskId") taskId: Long): Response<TaskDetailResponse>

    @Multipart
    @POST("api/devices/{deviceId}/screenshots")
    suspend fun uploadScreenshot(
        @Path("deviceId") deviceId: String,
        @Part image: MultipartBody.Part
    ): Response<ScreenshotResponse>

    @Multipart
    @POST("api/devices/{deviceId}/tasks/{taskId}/proof")
    suspend fun submitProof(
        @Path("deviceId") deviceId: String,
        @Path("taskId") taskId: Long,
        @Part("text") text: RequestBody?,
        @Part media: MultipartBody.Part?
    ): Response<ProofResponse>
}

data class TaskResponse(
    val id: Long,
    val name: String,
    val description: String?,
    val expected_proof: String?,
    val deadline_at: String,
    val status: String,
    val can_submit_proof: Boolean,
    val proof_status: String?
)

data class TaskDetailResponse(
    val id: Long,
    val name: String,
    val description: String?,
    val expected_proof: String?,
    val deadline_at: String,
    val status: String,
    val can_submit_proof: Boolean,
    val proof_status: String?,
    val proof: ProofResponse?
)

data class ScreenshotResponse(
    val id: Long,
    val url: String,
    val captured_at: String
)

data class ProofResponse(
    val id: Long,
    val text: String?,
    val status: String,
    val review_comment: String?,
    val media_url: String?,
    val created_at: String?
)
