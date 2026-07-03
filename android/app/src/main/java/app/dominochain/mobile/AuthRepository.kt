package app.dominochain.mobile

import app.dominochain.mobile.api.ApiService
import app.dominochain.mobile.api.AuthResponse
import app.dominochain.mobile.api.LoginRequest
import app.dominochain.mobile.api.RegisterAuthRequest
import app.dominochain.mobile.api.RetrofitClient

class AuthRepository {
    private val api = RetrofitClient.api

    suspend fun login(
        email: String,
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
                    email = email,
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
        email: String,
        password: String,
        passwordConfirmation: String,
        deviceId: String,
        nickname: String? = null,
        screenWidth: Int? = null,
        screenHeight: Int? = null,
        fcmToken: String? = null,
        name: String? = null
    ): Result<AuthResponse> {
        return try {
            val response = api.registerAuth(
                RegisterAuthRequest(
                    email = email,
                    password = password,
                    password_confirmation = passwordConfirmation,
                    nickname = nickname,
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

    suspend fun getShowcaseSettings(): Result<app.dominochain.mobile.api.ShowcaseSettingsResponse> {
        return try {
            val response = api.getShowcaseSettings()
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

    suspend fun updateShowcaseSettings(
        showcaseQuizEnabled: Boolean,
        showcaseSnakeEnabled: Boolean,
        showcaseDinoEnabled: Boolean,
        showcaseTetrisEnabled: Boolean,
        showcaseBackdoorEnabled: Boolean,
        showcaseQuizSecondsPerPoint: Int,
        showcaseSnakeSecondsPerFruit: Int,
        showcaseDinoSecondsPerObstacle: Int,
        showcaseTetrisSecondsPerLine: Int
    ): Result<app.dominochain.mobile.api.ShowcaseSettingsResponse> {
        return try {
            val response = api.updateShowcaseSettings(
                app.dominochain.mobile.api.ShowcaseSettingsRequest(
                    showcase_quiz_enabled = showcaseQuizEnabled,
                    showcase_snake_enabled = showcaseSnakeEnabled,
                    showcase_dino_enabled = showcaseDinoEnabled,
                    showcase_tetris_enabled = showcaseTetrisEnabled,
                    showcase_backdoor_enabled = showcaseBackdoorEnabled,
                    showcase_quiz_seconds_per_point = showcaseQuizSecondsPerPoint,
                    showcase_snake_seconds_per_fruit = showcaseSnakeSecondsPerFruit,
                    showcase_dino_seconds_per_obstacle = showcaseDinoSecondsPerObstacle,
                    showcase_tetris_seconds_per_line = showcaseTetrisSecondsPerLine
                )
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
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

    suspend fun getMe(): Result<app.dominochain.mobile.api.MeResponse> {
        return try {
            val response = api.getMe()
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

    suspend fun changePassword(currentPassword: String, newPassword: String, confirmation: String): Result<Unit> {
        return try {
            val response = api.changePassword(
                app.dominochain.mobile.api.ChangePasswordRequest(
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
