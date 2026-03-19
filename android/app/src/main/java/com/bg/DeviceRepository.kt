package com.bg

import com.bg.api.ChasterLockResponse
import com.bg.api.FcmTokenRequest
import com.bg.api.NameRequest
import com.bg.api.PermissionsRequest
import com.bg.api.ProofResponse
import com.bg.api.RetrofitClient
import com.bg.api.RegisterRequest
import com.bg.api.RegisterResponse
import com.bg.api.TaskDetailResponse
import com.bg.api.TaskResponse
import com.bg.api.WallpaperItemResponse
import com.bg.api.WallpaperResponse
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File

class DeviceRepository {
    private val api = RetrofitClient.api

    suspend fun register(deviceId: String, screenWidth: Int? = null, screenHeight: Int? = null, fcmToken: String? = null, name: String? = null): Result<RegisterResponse> {
        return try {
            val response = api.register(RegisterRequest(device_id = deviceId, screen_width = screenWidth, screen_height = screenHeight, fcm_token = fcmToken, name = name))
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception("Registration failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getWallpaper(deviceId: String): Result<WallpaperResponse?> {
        return try {
            val response = api.getWallpaper(deviceId)
            if (response.isSuccessful) {
                Result.success(response.body())
            } else if (response.code() == 404) {
                Result.success(null)
            } else {
                Result.failure(Exception("Failed to get wallpaper: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateFcmToken(deviceId: String, fcmToken: String): Result<Unit> {
        return try {
            val response = api.updateFcmToken(deviceId, FcmTokenRequest(fcm_token = fcmToken))
            if (response.isSuccessful) Result.success(Unit) else Result.failure(Exception("Failed: ${response.code()}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateName(deviceId: String, name: String?): Result<Unit> {
        return try {
            val response = api.updateName(deviceId, NameRequest(name = name))
            if (response.isSuccessful) Result.success(Unit) else Result.failure(Exception("Failed: ${response.code()}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun reportPermissionsStatus(deviceId: String, permissionsOk: Boolean, permissionsMissing: List<String> = emptyList()): Result<Unit> {
        return try {
            val response = api.updatePermissions(deviceId, PermissionsRequest(permissions_ok = permissionsOk, permissions_missing = permissionsMissing.takeIf { it.isNotEmpty() }))
            if (response.isSuccessful) Result.success(Unit) else Result.failure(Exception("Failed: ${response.code()}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getWallpapers(deviceId: String): Result<List<WallpaperItemResponse>> {
        return try {
            val response = api.getWallpapers(deviceId)
            if (response.isSuccessful) {
                Result.success(response.body() ?: emptyList())
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getChasterLock(): Result<ChasterLockResponse?> {
        return try {
            val response = api.getChasterLock()
            if (response.isSuccessful) {
                Result.success(response.body())
            } else if (response.code() == 401) {
                Result.success(ChasterLockResponse(lock = null, error = "Chaster non connecté"))
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getTasks(deviceId: String): Result<List<TaskResponse>> {
        return try {
            val response = api.getTasks(deviceId)
            if (response.isSuccessful) {
                Result.success(response.body() ?: emptyList())
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getTaskDetail(deviceId: String, taskId: Long): Result<TaskDetailResponse> {
        return try {
            val response = api.getTaskDetail(deviceId, taskId)
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception("Failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun uploadScreenshot(deviceId: String, imageFile: File): Result<Unit> {
        return try {
            val part = MultipartBody.Part.createFormData("image", imageFile.name, imageFile.asRequestBody("image/jpeg".toMediaType()))
            val response = api.uploadScreenshot(deviceId, part)
            if (response.isSuccessful) Result.success(Unit) else Result.failure(Exception("Upload failed: ${response.code()}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun submitProof(deviceId: String, taskId: Long, text: String?, mediaFile: File?): Result<ProofResponse> {
        return try {
            val textBody = (text ?: "").toRequestBody("text/plain".toMediaType())
            val mediaPart = mediaFile?.let { file ->
                val contentType = when {
                    file.name.endsWith(".mp4", true) -> "video/mp4"
                    file.name.endsWith(".mov", true) -> "video/quicktime"
                    else -> "image/*"
                }
                MultipartBody.Part.createFormData("media", file.name, file.asRequestBody(contentType.toMediaType()))
            }
            val response = api.submitProof(deviceId, taskId, textBody, mediaPart)
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                val errorBody = response.errorBody()?.string() ?: ""
                Result.failure(Exception("Failed: ${response.code()} - $errorBody"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
