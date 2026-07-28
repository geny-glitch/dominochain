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

data class CornertimeVoicePrompts(
    val intro: String? = null,
    val stop_moving: String? = null,
    val return_to_position: String? = null
)

data class CornertimeConfigResponse(
    val sensitivity: String? = null,
    val detector: String? = null,
    val diff_sensitivity: Double? = null,
    val pixel_threshold: Int? = null,
    val motion_threshold: Double? = null,
    val drift_threshold: Double? = null,
    val drift_hold_ms: Int? = null,
    val drift_pixel_delta: Int? = null,
    val cell_active_below: Int? = null,
    val matrix_width: Int? = null,
    val matrix_height: Int? = null,
    val source_width: Int? = null,
    val source_height: Int? = null,
    val pixel_change_delta: Double? = null,
    val violation_cooldown_seconds: Int? = null,
    val calibration_seconds: Int? = null,
    val source_enabled: Boolean? = null,
    val locale: String? = null,
    val voice: CornertimeVoicePrompts? = null,
    val allowed_durations_minutes: List<Int>? = null
)

data class CornertimeSessionRequest(
    val client: String = "android",
    val duration_minutes: Int
)

data class CornertimeSessionPayload(
    val id: Long,
    val status: String? = null,
    val client: String? = null,
    val started_at: String? = null,
    val ended_at: String? = null,
    val planned_duration_seconds: Int? = null,
    val planned_duration_minutes: Int? = null,
    val ends_at: String? = null,
    val violation_count: Int? = null
)

data class CornertimeSessionStartResponse(
    val session: CornertimeSessionPayload,
    val config: CornertimeConfigResponse? = null
)

data class CornertimeSessionStopResponse(
    val session: CornertimeSessionPayload,
    val early_stop: Boolean? = null,
    val actions_executed: List<Map<String, Any?>>? = null
)

data class CornertimeViolationRequest(
    val motion_score: Double? = null,
    val detected_at: String? = null,
    val client_violation_id: String? = null
)

data class CornertimeViolationPayload(
    val id: Long? = null,
    val status: String? = null,
    val detected_at: String? = null,
    val motion_score: Double? = null
)

data class CornertimeViolationResponse(
    val status: String? = null,
    val cooldown_remaining_seconds: Int? = null,
    val violation: CornertimeViolationPayload? = null,
    val session: CornertimeSessionPayload? = null,
    val error: String? = null
)

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

    @GET("api/cornertime/config")
    suspend fun getCornertimeConfig(): Response<CornertimeConfigResponse>

    @POST("api/cornertime/sessions")
    suspend fun startCornertimeSession(@Body request: CornertimeSessionRequest): Response<CornertimeSessionStartResponse>

    @PATCH("api/cornertime/sessions/{id}/stop")
    suspend fun stopCornertimeSession(@Path("id") id: Long): Response<CornertimeSessionStopResponse>

    @POST("api/cornertime/sessions/{id}/violations")
    suspend fun reportCornertimeViolation(
        @Path("id") id: Long,
        @Body request: CornertimeViolationRequest
    ): Response<CornertimeViolationResponse>

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

    @GET("api/wallpaper/config")
    suspend fun getWallpaperConfig(): Response<WallpaperConfigResponse>

    @PATCH("api/wallpaper/config")
    suspend fun updateWallpaperConfig(@Body body: WallpaperConfigUpdateRequest): Response<WallpaperConfigResponse>

    @GET("api/wallpaper/scenario_schema")
    suspend fun getWallpaperScenarioSchema(): Response<WallpaperScenarioSchemaResponse>

    @Multipart
    @POST("api/wallpaper/upload")
    suspend fun uploadWallpaperBeta(@Part image: MultipartBody.Part): Response<WallpaperUploadResponse>

    @POST("api/wallpaper/verification_sessions")
    suspend fun startWallpaperVerificationSession(
        @Body body: WallpaperVerificationSessionRequest
    ): Response<WallpaperVerificationSessionStartResponse>

    @GET("api/leverage_photos")
    suspend fun getLeveragePhotos(): Response<LeveragePhotosListResponse>

    @GET("api/leverage_photos/{id}")
    suspend fun getLeveragePhoto(@Path("id") id: Long): Response<LeveragePhotoResponse>

    @Multipart
    @POST("api/leverage_photos")
    suspend fun createLeveragePhoto(
        @Part original_image: MultipartBody.Part,
        @Part teaser_image: MultipartBody.Part,
        @Part censored_image: MultipartBody.Part?
    ): Response<LeveragePhotoResponse>

    @Multipart
    @POST("api/leverage_photos/{id}/censor")
    suspend fun censorLeveragePhoto(
        @Path("id") id: Long,
        @Part censored_image: MultipartBody.Part
    ): Response<LeveragePhotoResponse>

    @Multipart
    @POST("api/leverage_photos/{id}/start")
    suspend fun startLeveragePhotoTimer(
        @Path("id") id: Long,
        @Part tlock_blob: MultipartBody.Part,
        @Part("drand_round") drandRound: RequestBody,
        @Part("locked_until") lockedUntil: RequestBody,
        @Part("duration_seconds") durationSeconds: RequestBody,
        @Part("drand_chain_hash") chainHash: RequestBody?
    ): Response<LeveragePhotoTimerResponse>

    @Multipart
    @POST("api/leverage_photos/{id}/add_time")
    suspend fun addLeveragePhotoTime(
        @Path("id") id: Long,
        @Part tlock_blob: MultipartBody.Part,
        @Part("drand_round") drandRound: RequestBody,
        @Part("locked_until") lockedUntil: RequestBody,
        @Part("added_seconds") addedSeconds: RequestBody
    ): Response<LeveragePhotoTimerResponse>

    @GET("api/leverage_photos/{id}/tlock_blob")
    suspend fun getLeveragePhotoTlockBlob(@Path("id") id: Long): Response<okhttp3.ResponseBody>

    @GET("api/leverage_photos/{id}/original")
    suspend fun getLeveragePhotoOriginal(@Path("id") id: Long): Response<okhttp3.ResponseBody>

    @GET("api/leverage_photos/{id}/decrypt_payload")
    suspend fun getLeveragePhotoDecryptPayload(@Path("id") id: Long): Response<okhttp3.ResponseBody>

    @Multipart
    @POST("api/leverage_photos/{id}/restore_original")
    suspend fun restoreLeveragePhotoOriginal(
        @Path("id") id: Long,
        @Part original_image: MultipartBody.Part
    ): Response<LeveragePhotoTimerResponse>

    @POST("api/leverage_photos/{id}/set_as_wallpaper")
    suspend fun setLeveragePhotoAsWallpaper(
        @Path("id") id: Long,
        @Body body: LeveragePhotoWallpaperRequest
    ): Response<LeveragePhotoWallpaperResponse>
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

data class WallpaperConfigResponse(
    val source_enabled: Boolean = false,
    val enabled: Boolean = false,
    val check_interval_minutes: Int = 60,
    val dismiss_apps_before_capture: Boolean = false,
    val scenarios: WallpaperScenariosWrapper? = null,
    val verification_session: WallpaperVerificationSessionInfo? = null,
    val device: WallpaperDeviceInfo? = null,
    val locked: Boolean = false,
    val boss_controls: Boolean = false,
    val config_locked: Boolean = false,
    val allowed_duration_hours: List<Int> = emptyList(),
    val leverage_action_enabled: Boolean = false,
    val leverage_photos: List<WallpaperLeveragePhotoSummary> = emptyList()
)

data class WallpaperScenariosWrapper(
    val scenarios: List<WallpaperScenarioDto> = emptyList()
)

data class WallpaperScenarioDto(
    val id: String? = null,
    val event: String,
    val trigger: Map<String, Any?> = emptyMap(),
    val actions: List<WallpaperScenarioActionDto> = emptyList()
)

data class WallpaperScenarioActionDto(
    val possibility_id: String,
    val config: Map<String, Any?> = emptyMap()
)

data class WallpaperVerificationSessionInfo(
    val active: Boolean = false,
    val id: Long? = null,
    val ends_at: String? = null,
    val started_at: String? = null,
    val duration_hours: Int? = null,
    val remaining_seconds: Int? = null,
    val config_locked: Boolean? = null
)

data class WallpaperDeviceInfo(
    val connected: Boolean = false,
    val name: String? = null,
    val permissions_ok: Boolean = false,
    val permissions_missing: List<String> = emptyList(),
    val has_current_wallpaper: Boolean = false,
    val fcm_token_present: Boolean = false,
    val reachable: Boolean = false,
    val last_seen_at: String? = null
)

data class WallpaperLeveragePhotoSummary(
    val id: Long,
    val status: String? = null,
    val locked_until: String? = null,
    val teaser_url: String? = null,
    val censored_url: String? = null
)

data class WallpaperConfigUpdateRequest(
    val enabled: Boolean? = null,
    val check_interval_minutes: Int? = null,
    val dismiss_apps_before_capture: Boolean? = null,
    val scenarios: WallpaperScenariosWrapper? = null
)

data class WallpaperScenarioSchemaResponse(
    val events: Map<String, WallpaperEventSchemaDto> = emptyMap(),
    val actions: List<WallpaperActionSchemaDto> = emptyList()
)

data class WallpaperEventSchemaDto(
    val trigger_fields: Map<String, Map<String, Any?>> = emptyMap()
)

data class WallpaperActionSchemaDto(
    val possibility_id: String,
    val catalog_id: String? = null,
    val config_schema: Map<String, Map<String, Any?>> = emptyMap()
)

data class WallpaperUploadResponse(
    val id: Long,
    val url: String,
    val updated_at: String
)

data class WallpaperVerificationSessionRequest(
    val duration_hours: Int
)

data class WallpaperVerificationSessionStartResponse(
    val session: WallpaperVerificationSessionInfo
)

data class LeveragePhotosListResponse(
    val photos: List<LeveragePhotoResponse> = emptyList()
)

data class LeveragePhotoResponse(
    val id: Long,
    val status: String,
    val locked_until: String? = null,
    val tlock_layer_count: Int = 0,
    val original_filename: String? = null,
    val can_start_timer: Boolean = false,
    val can_add_time: Boolean = false,
    val can_censor: Boolean = false,
    val has_original: Boolean = false,
    val has_censored: Boolean = false,
    val has_teaser: Boolean = false,
    val teaser_url: String? = null,
    val censored_url: String? = null,
    val created_at: String? = null,
    val initial_duration_seconds: Int? = null,
    val drand_rounds: List<Long>? = null,
    val wallpaper_ready: Boolean = false
)

data class LeveragePhotoTimerResponse(
    val status: String? = null,
    val locked_until: String? = null,
    val layers: Int? = null,
    val restored: Boolean? = null,
    val photo: LeveragePhotoResponse? = null,
    val error: String? = null
)

data class LeveragePhotoWallpaperRequest(
    val variant: String = "display"
)

data class LeveragePhotoWallpaperResponse(
    val ok: Boolean = false,
    val photo: LeveragePhotoResponse? = null,
    val error: String? = null
)
