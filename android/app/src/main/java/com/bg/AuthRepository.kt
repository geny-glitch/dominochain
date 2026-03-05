package com.bg

import com.bg.api.ApiService
import com.bg.api.AuthResponse
import com.bg.api.LoginRequest
import com.bg.api.RegisterAuthRequest
import com.bg.api.RetrofitClient

class AuthRepository {
    private val api = RetrofitClient.api

    suspend fun login(
        nickname: String,
        password: String,
        deviceId: String,
        screenWidth: Int? = null,
        screenHeight: Int? = null,
        fcmToken: String? = null,
        name: String? = null
    ): Result<AuthResponse> {
        return try {
            val response = api.login(
                LoginRequest(
                    nickname = nickname,
                    password = password,
                    device_id = deviceId,
                    screen_width = screenWidth,
                    screen_height = screenHeight,
                    fcm_token = fcmToken,
                    name = name
                )
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                val errorBody = response.errorBody()?.string() ?: ""
                val error = try {
                    com.google.gson.Gson().fromJson(errorBody, Map::class.java)?.get("error")?.toString() ?: "Login failed"
                } catch (_: Exception) {
                    "Login failed: ${response.code()}"
                }
                Result.failure(Exception(error))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun register(
        nickname: String,
        password: String,
        passwordConfirmation: String,
        deviceId: String,
        screenWidth: Int? = null,
        screenHeight: Int? = null,
        fcmToken: String? = null,
        name: String? = null
    ): Result<AuthResponse> {
        return try {
            val response = api.registerAuth(
                RegisterAuthRequest(
                    nickname = nickname,
                    password = password,
                    password_confirmation = passwordConfirmation,
                    device_id = deviceId,
                    screen_width = screenWidth,
                    screen_height = screenHeight,
                    fcm_token = fcmToken,
                    name = name
                )
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                val errorBody = response.errorBody()?.string() ?: ""
                val error = try {
                    com.google.gson.Gson().fromJson(errorBody, Map::class.java)?.get("error")?.toString() ?: "Registration failed"
                } catch (_: Exception) {
                    "Registration failed: ${response.code()}"
                }
                Result.failure(Exception(error))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun changePassword(currentPassword: String, newPassword: String, confirmation: String): Result<Unit> {
        return try {
            val response = api.changePassword(
                com.bg.api.ChangePasswordRequest(
                    current_password = currentPassword,
                    password = newPassword,
                    password_confirmation = confirmation
                )
            )
            if (response.isSuccessful) Result.success(Unit)
            else {
                val errorBody = response.errorBody()?.string() ?: ""
                val error = try {
                    com.google.gson.Gson().fromJson(errorBody, Map::class.java)?.get("error")?.toString() ?: "Erreur"
                } catch (_: Exception) {
                    "Erreur: ${response.code()}"
                }
                Result.failure(Exception(error))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun sendControlRequest(bossNickname: String): Result<String> {
        return try {
            val response = api.sendControlRequest(ApiService.ControlRequestBody(boss_nickname = bossNickname))
            if (response.isSuccessful) {
                Result.success(response.body()?.message ?: "Demande envoyée")
            } else {
                val errorBody = response.errorBody()?.string() ?: ""
                val error = try {
                    com.google.gson.Gson().fromJson(errorBody, Map::class.java)?.get("error")?.toString() ?: "Erreur"
                } catch (_: Exception) {
                    "Erreur: ${response.code()}"
                }
                Result.failure(Exception(error))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
