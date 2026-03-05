package com.bg

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.bg.api.RetrofitClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

class BgAccessibilityService : AccessibilityService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
    }

    fun captureAndUpload() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val hardwareBuffer = screenshot.hardwareBuffer
                        val colorSpace = screenshot.colorSpace
                        serviceScope.launch {
                            try {
                                val bitmap = Bitmap.wrapHardwareBuffer(hardwareBuffer, colorSpace)
                                hardwareBuffer.close()
                                if (bitmap != null) {
                                    val file = saveBitmapToFile(bitmap)
                                    bitmap.recycle()
                                    if (file != null) uploadScreenshot(file)
                                    else Log.e(TAG, "Failed to save bitmap to file")
                                } else {
                                    Log.e(TAG, "wrapHardwareBuffer returned null")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Screenshot processing failed", e)
                            }
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "Screenshot capture failed with errorCode=$errorCode")
                    }
                }
            )
        } else {
            Log.e(TAG, "takeScreenshot requires Android 11+ (API 30)")
        }
    }

    private fun saveBitmapToFile(bitmap: Bitmap): File? {
        return try {
            val file = File(cacheDir, "screenshot_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            }
            file
        } catch (e: Exception) {
            Log.e(TAG, "Save bitmap failed", e)
            null
        }
    }

    private suspend fun uploadScreenshot(file: File) {
        try {
            val app = applicationContext as? BgApplication ?: return
            RetrofitClient.sessionManager = app.sessionManager
            val deviceId = app.sessionManager.deviceId
            if (deviceId.isNullOrBlank()) {
                Log.e(TAG, "Upload failed: deviceId is null")
                return
            }
            if (app.sessionManager.token.isNullOrBlank()) {
                Log.e(TAG, "Upload failed: token is null")
                return
            }
            val result = DeviceRepository().uploadScreenshot(deviceId, file)
            result.fold(
                onSuccess = {
                    Log.d(TAG, "Upload success")
                    file.delete()
                },
                onFailure = { e ->
                    Log.e(TAG, "Upload failed: ${e.message}", e)
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "Upload failed", e)
        }
    }

    companion object {
        private const val TAG = "BgAccessibility"

        @Volatile
        private var instance: BgAccessibilityService? = null

        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val componentName = "${context.packageName}/.BgAccessibilityService"
            return enabledServices.split(":").any {
                it.equals(componentName, ignoreCase = true)
            }
        }

        /** Returns true if the service is running and the capture was dispatched. */
        fun requestCapture(): Boolean {
            val svc = instance ?: return false
            svc.captureAndUpload()
            return true
        }
    }
}
