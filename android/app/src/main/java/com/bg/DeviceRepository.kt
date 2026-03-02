package com.bg

import com.bg.api.FcmTokenRequest
import com.bg.api.RetrofitClient
import com.bg.api.RegisterRequest
import com.bg.api.RegisterResponse
import com.bg.api.WallpaperResponse

class DeviceRepository {
    private val api = RetrofitClient.api

    suspend fun register(deviceId: String, screenWidth: Int? = null, screenHeight: Int? = null, fcmToken: String? = null): Result<RegisterResponse> {
        return try {
            val response = api.register(RegisterRequest(device_id = deviceId, screen_width = screenWidth, screen_height = screenHeight, fcm_token = fcmToken))
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
}
