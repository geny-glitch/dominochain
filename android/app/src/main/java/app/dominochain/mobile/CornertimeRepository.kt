package app.dominochain.mobile

import app.dominochain.mobile.api.CornertimeConfigResponse
import app.dominochain.mobile.api.CornertimeSessionRequest
import app.dominochain.mobile.api.CornertimeSessionStartResponse
import app.dominochain.mobile.api.CornertimeSessionStopResponse
import app.dominochain.mobile.api.CornertimeViolationRequest
import app.dominochain.mobile.api.CornertimeViolationResponse
import app.dominochain.mobile.api.RetrofitClient

class CornertimeRepository {
    private val api = RetrofitClient.api

    suspend fun getConfig(): Result<CornertimeConfigResponse> {
        return try {
            val response = api.getCornertimeConfig()
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

    suspend fun startSession(durationMinutes: Int): Result<CornertimeSessionStartResponse> {
        return try {
            val response = api.startCornertimeSession(
                CornertimeSessionRequest(client = "android", duration_minutes = durationMinutes)
            )
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

    suspend fun stopSession(sessionId: Long): Result<CornertimeSessionStopResponse> {
        return try {
            val response = api.stopCornertimeSession(sessionId)
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

    suspend fun reportViolation(
        sessionId: Long,
        motionScore: Double,
        clientViolationId: String
    ): Result<CornertimeViolationResponse> {
        return try {
            val response = api.reportCornertimeViolation(
                sessionId,
                CornertimeViolationRequest(
                    motion_score = motionScore,
                    detected_at = java.time.Instant.now().toString(),
                    client_violation_id = clientViolationId
                )
            )
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

    private fun errorMessage(code: Int, body: String?): String {
        if (!body.isNullOrBlank()) {
            val match = Regex("\"error\"\\s*:\\s*\"([^\"]+)\"").find(body)
            if (match != null) return match.groupValues[1]
        }
        return "Request failed: $code"
    }
}
