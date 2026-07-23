package app.dominochain.mobile

import app.dominochain.mobile.api.LeveragePhotoResponse
import app.dominochain.mobile.api.LeveragePhotoTimerResponse
import app.dominochain.mobile.api.LeveragePhotoWallpaperRequest
import app.dominochain.mobile.api.LeveragePhotoWallpaperResponse
import app.dominochain.mobile.api.LeveragePhotosListResponse
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.api.WallpaperConfigResponse
import app.dominochain.mobile.api.WallpaperConfigUpdateRequest
import app.dominochain.mobile.api.WallpaperScenarioSchemaResponse
import app.dominochain.mobile.api.WallpaperUploadResponse
import app.dominochain.mobile.api.WallpaperVerificationSessionRequest
import app.dominochain.mobile.api.WallpaperVerificationSessionStartResponse
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.ResponseBody
import java.io.File

class WallpaperRepository {
    private val api = RetrofitClient.api

    suspend fun getConfig(): Result<WallpaperConfigResponse> = apiCall {
        api.getWallpaperConfig()
    }

    suspend fun updateConfig(request: WallpaperConfigUpdateRequest): Result<WallpaperConfigResponse> = apiCall {
        api.updateWallpaperConfig(request)
    }

    suspend fun getScenarioSchema(): Result<WallpaperScenarioSchemaResponse> = apiCall {
        api.getWallpaperScenarioSchema()
    }

    suspend fun upload(imageFile: File): Result<WallpaperUploadResponse> {
        return try {
            val mime = mimeFor(imageFile)
            val part = MultipartBody.Part.createFormData(
                "image",
                imageFile.name,
                imageFile.asRequestBody(mime.toMediaType())
            )
            val response = api.uploadWallpaperBeta(part)
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun startVerificationSession(durationHours: Int): Result<WallpaperVerificationSessionStartResponse> =
        apiCall {
            api.startWallpaperVerificationSession(WallpaperVerificationSessionRequest(durationHours))
        }

    private suspend fun <T> apiCall(block: suspend () -> retrofit2.Response<T>): Result<T> {
        return try {
            val response = block()
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    companion object {
        fun mimeFor(file: File): String {
            return when {
                file.name.endsWith(".png", true) -> "image/png"
                file.name.endsWith(".webp", true) -> "image/webp"
                else -> "image/jpeg"
            }
        }

        fun errorMessage(code: Int, body: String?): String {
            if (!body.isNullOrBlank()) {
                val match = Regex("\"error\"\\s*:\\s*\"([^\"]+)\"").find(body)
                if (match != null) return match.groupValues[1]
            }
            return "Request failed: $code"
        }
    }
}

class LeveragePhotoRepository {
    private val api = RetrofitClient.api

    suspend fun list(): Result<LeveragePhotosListResponse> = apiCall { api.getLeveragePhotos() }

    suspend fun get(id: Long): Result<LeveragePhotoResponse> = apiCall { api.getLeveragePhoto(id) }

    suspend fun create(original: File, teaser: File, censored: File?): Result<LeveragePhotoResponse> {
        return try {
            val response = api.createLeveragePhoto(
                part("original_image", original),
                part("teaser_image", teaser),
                censored?.let { part("censored_image", it) }
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun censor(id: Long, censored: File): Result<LeveragePhotoResponse> {
        return try {
            val response = api.censorLeveragePhoto(id, part("censored_image", censored))
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun startTimer(
        id: Long,
        tlockFile: File,
        drandRound: Long,
        lockedUntilIso: String,
        durationSeconds: Int,
        chainHash: String?
    ): Result<LeveragePhotoTimerResponse> {
        return try {
            val response = api.startLeveragePhotoTimer(
                id,
                textPart("tlock_blob", tlockFile),
                drandRound.toString().toRequestBody("text/plain".toMediaType()),
                lockedUntilIso.toRequestBody("text/plain".toMediaType()),
                durationSeconds.toString().toRequestBody("text/plain".toMediaType()),
                chainHash?.toRequestBody("text/plain".toMediaType())
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun addTime(
        id: Long,
        tlockFile: File,
        drandRound: Long,
        lockedUntilIso: String,
        addedSeconds: Int
    ): Result<LeveragePhotoTimerResponse> {
        return try {
            val response = api.addLeveragePhotoTime(
                id,
                textPart("tlock_blob", tlockFile),
                drandRound.toString().toRequestBody("text/plain".toMediaType()),
                lockedUntilIso.toRequestBody("text/plain".toMediaType()),
                addedSeconds.toString().toRequestBody("text/plain".toMediaType())
            )
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun downloadTlockBlob(id: Long): Result<ByteArray> = downloadBytes { api.getLeveragePhotoTlockBlob(id) }

    suspend fun downloadOriginal(id: Long): Result<ByteArray> = downloadBytes { api.getLeveragePhotoOriginal(id) }

    suspend fun downloadDecryptPayload(id: Long): Result<ByteArray> = downloadBytes { api.getLeveragePhotoDecryptPayload(id) }

    suspend fun restoreOriginal(id: Long, original: File): Result<LeveragePhotoTimerResponse> {
        return try {
            val response = api.restoreLeveragePhotoOriginal(id, part("original_image", original))
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun setAsWallpaper(id: Long, variant: String): Result<LeveragePhotoWallpaperResponse> = apiCall {
        api.setLeveragePhotoAsWallpaper(id, LeveragePhotoWallpaperRequest(variant = variant))
    }

    private fun part(name: String, file: File): MultipartBody.Part {
        val mime = WallpaperRepository.mimeFor(file)
        return MultipartBody.Part.createFormData(name, file.name, file.asRequestBody(mime.toMediaType()))
    }

    private fun textPart(name: String, file: File): MultipartBody.Part {
        return MultipartBody.Part.createFormData(name, file.name, file.asRequestBody("text/plain".toMediaType()))
    }

    private suspend fun downloadBytes(block: suspend () -> retrofit2.Response<ResponseBody>): Result<ByteArray> {
        return try {
            val response = block()
            if (response.isSuccessful) {
                val bytes = response.body()?.bytes()
                if (bytes != null) Result.success(bytes)
                else Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private suspend fun <T> apiCall(block: suspend () -> retrofit2.Response<T>): Result<T> {
        return try {
            val response = block()
            if (response.isSuccessful) {
                response.body()?.let { Result.success(it) }
                    ?: Result.failure(Exception("Empty response"))
            } else {
                Result.failure(Exception(WallpaperRepository.errorMessage(response.code(), response.errorBody()?.string())))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
