package com.bg

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Transparent activity that requests MediaProjection permission.
 * Used when FCM "take_screenshot" arrives and ScreenshotCaptureService is not running.
 */
class MediaProjectionRequestActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.w(TAG, "onCreate - requesting MediaProjection")
        val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(
            projectionManager.createScreenCaptureIntent(),
            REQUEST_MEDIA_PROJECTION
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            Log.w(TAG, "onActivityResult resultCode=$resultCode data=${data != null}")
            if (resultCode == RESULT_OK && data != null) {
                Log.w(TAG, "Starting ScreenshotCaptureService")
                val serviceIntent = Intent(this, ScreenshotCaptureService::class.java).apply {
                    action = ScreenshotCaptureService.ACTION_START
                    putExtra(ScreenshotCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenshotCaptureService.EXTRA_RESULT_DATA, data)
                    putExtra(ScreenshotCaptureService.EXTRA_CAPTURE_IMMEDIATELY, true)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
            }
            finish()
        }
    }

    companion object {
        private const val TAG = "MediaProjectionReq"
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }
}
