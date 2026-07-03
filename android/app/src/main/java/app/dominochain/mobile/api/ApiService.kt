package app.dominochain.mobile.api

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
import retrofit2.http.Query

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
    val email: String,
    val password: String,
    val device_id: String,
    val screen_width: Int? = null,
    val screen_height: Int? = null,
    val fcm_token: String? = null,
    val name: String? = null
)

data class RegisterAuthRequest(
    val email: String,
    val password: String,
    val password_confirmation: String,
    val nickname: String? = null,
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

data class MeResponse(
    val nickname: String,
    val boss_nickname: String?,
    val role: String? = null
)

data class ShowcaseSettingsResponse(
    val showcase_quiz_enabled: Boolean,
    val showcase_snake_enabled: Boolean,
    val showcase_dino_enabled: Boolean? = true,
    val showcase_tetris_enabled: Boolean? = true,
    val showcase_backdoor_enabled: Boolean,
    val showcase_quiz_seconds_per_point: Int? = null,
    val showcase_snake_seconds_per_fruit: Int? = null,
    val showcase_dino_seconds_per_obstacle: Int? = null,
    val showcase_tetris_seconds_per_line: Int? = null
)

data class ShowcaseSettingsRequest(
    val showcase_quiz_enabled: Boolean,
    val showcase_snake_enabled: Boolean,
    val showcase_dino_enabled: Boolean,
    val showcase_tetris_enabled: Boolean,
    val showcase_backdoor_enabled: Boolean,
    val showcase_quiz_seconds_per_point: Int,
    val showcase_snake_seconds_per_fruit: Int,
    val showcase_dino_seconds_per_obstacle: Int,
    val showcase_tetris_seconds_per_line: Int
)

data class ChangePasswordRequest(
    val current_password: String,
    val password: String,
    val password_confirmation: String
)

data class WallpaperResponse(
    val url: String,
    val updated_at: String
)

data class WallpaperItemResponse(
    val id: Long,
    val url: String,
    val created_at: String,
    val first_downloaded_at: String?
)

data class FcmTokenRequest(val fcm_token: String)

data class NameRequest(val name: String?)
data class PermissionsRequest(val permissions_ok: Boolean, val permissions_missing: List<String>? = null)
data class CigaretteEntryRequest(val count: Int = 1)

interface ApiService {
    @POST("api/auth/login")
    suspend fun login(@Body request: LoginRequest): Response<AuthResponse>

    @POST("api/auth/register")
    suspend fun registerAuth(@Body request: RegisterAuthRequest): Response<AuthResponse>

    @GET("api/auth/me")
    suspend fun getMe(): Response<MeResponse>

    @GET("api/showcase_settings")
    suspend fun getShowcaseSettings(): Response<ShowcaseSettingsResponse>

    @PATCH("api/showcase_settings")
    suspend fun updateShowcaseSettings(@Body body: ShowcaseSettingsRequest): Response<ShowcaseSettingsResponse>

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

    @GET("api/devices/{deviceId}/wallpapers")
    suspend fun getWallpapers(@Path("deviceId") deviceId: String): Response<List<WallpaperItemResponse>>

    @GET("api/chaster/lock")
    suspend fun getChasterLock(): Response<ChasterLockResponse>

    @GET("api/chaster/time_events")
    suspend fun getChasterTimeEvents(
        @Query("page") page: Int,
        @Query("per_page") perPage: Int
    ): Response<ChasterTimeEventsResponse>

    @GET("api/cigarettes")
    suspend fun getCigarettes(): Response<CigaretteTrackerResponse>

    @POST("api/cigarettes")
    suspend fun createCigaretteEntry(@Body request: CigaretteEntryRequest): Response<CigaretteTrackerResponse>

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
    val proof: ProofResponse?,
    val punishments: List<PunishmentResponse>? = null
)

data class PunishmentResponse(
    val id: Long,
    val message: String?,
    val created_at: String
)

data class ScreenshotResponse(
    val id: Long,
    val url: String,
    val captured_at: String
)

data class ChasterLockResponse(
    val lock: ChasterLock?,
    val error: String? = null,
    val pishock_enabled: Boolean? = null,
    val showcase_quiz_seconds_per_point: Int? = null,
    val showcase_snake_seconds_per_fruit: Int? = null,
    val showcase_dino_seconds_per_obstacle: Int? = null,
    val showcase_tetris_seconds_per_line: Int? = null
)

data class ChasterLock(
    val id: String?,
    val title: String?,
    val end_date: String?,
    val is_frozen: Boolean,
    val remaining_seconds: Int?,
    val display_remaining_time: Boolean = true
)

data class ChasterTimeEventsResponse(
    val events: List<ChasterTimeEvent> = emptyList(),
    val meta: PaginationMeta? = null
)

data class ChasterTimeEvent(
    val id: Long,
    val lock_id: String?,
    val seconds: Int,
    val source: String?,
    val source_label: String?,
    val summary: String?,
    val occurred_at: String?
)

data class PaginationMeta(
    val page: Int,
    val per_page: Int,
    val total_count: Int,
    val total_pages: Int,
    val next_page: Int?
)

data class CigaretteTrackerResponse(
    val today_count: Int? = null,
    val today: CigaretteHistoryItem? = null,
    val history: List<CigaretteHistoryItem> = emptyList(),
    val seconds_per_cigarette: Int? = null,
    val entry: CigaretteEntryResponse? = null,
    val latest_entry: CigaretteEntryResponse? = null
)

data class CigaretteHistoryItem(
    val date: String,
    val count: Int,
    val chaster_seconds: Int? = null
)

data class CigaretteEntryResponse(
    val id: Long?,
    val count: Int,
    val smoked_on: String?,
    val smoked_at: String?,
    val chaster_seconds: Int,
    val chaster_applied: Boolean,
    val chaster_error: String?
)

data class ProofResponse(
    val id: Long,
    val text: String?,
    val status: String,
    val review_comment: String?,
    val media_url: String?,
    val created_at: String?
)
