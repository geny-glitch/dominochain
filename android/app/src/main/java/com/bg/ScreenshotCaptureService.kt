package com.bg

import com.bg.api.RetrofitClient
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

class ScreenshotCaptureService : Service() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val handler = Handler(Looper.getMainLooper())

    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null

    private var resultCode: Int = -1
    private var resultData: Intent? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                screenshotReceiver,
                android.content.IntentFilter(ACTION_CAPTURE_SCREENSHOT),
                RECEIVER_NOT_EXPORTED
            )
        } else {
            registerReceiver(screenshotReceiver, android.content.IntentFilter(ACTION_CAPTURE_SCREENSHOT))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                if (resultCode != -1 && resultData != null) {
                    startForeground()
                    setupMediaProjection()
                    if (intent.getBooleanExtra(EXTRA_CAPTURE_IMMEDIATELY, false)) {
                        captureAndUpload()
                    }
                } else {
                    stopSelf()
                }
            }
            ACTION_CAPTURE -> {
                captureAndUpload()
            }
        }
        return START_STICKY
    }

    private fun startForeground() {
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                NotificationHelper.CHANNEL_ID_DEFAULT,
                "OTB",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            (getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager)
                .createNotificationChannel(channel)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, NotificationHelper.CHANNEL_ID_DEFAULT)
            .setContentTitle("OTB")
            .setContentText("Peut capturer l'écran à la demande")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun setupMediaProjection() {
        val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, resultData!!)
        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                mediaProjection = null
                stopSelf()
            }
        }, handler)
    }

    private val screenshotReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == ACTION_CAPTURE_SCREENSHOT) {
                captureAndUpload()
            }
        }
    }

    private fun captureAndUpload() {
        serviceScope.launch {
            try {
                val bitmap = captureScreen()
                if (bitmap != null) {
                    val file = saveBitmapToFile(bitmap)
                    bitmap.recycle()
                    file?.let { uploadScreenshot(it) }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Capture failed", e)
            }
        }
    }

    private fun captureScreen(): Bitmap? {
        val projection = mediaProjection ?: return null
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        virtualDisplay = projection.createVirtualDisplay(
            "ScreenshotCapture",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface,
            null,
            handler
        )

        Thread.sleep(150)

        var bitmap: Bitmap? = null
        try {
            val image = imageReader?.acquireLatestImage()
            if (image != null) {
                bitmap = imageToBitmap(image, width, height)
                image.close()
            }
        } finally {
            virtualDisplay?.release()
            virtualDisplay = null
            imageReader?.close()
            imageReader = null
        }
        return bitmap
    }

    private fun imageToBitmap(image: Image, width: Int, height: Int): Bitmap {
        val planes = image.planes
        val buffer = planes[0].buffer
        val pixelStride = planes[0].pixelStride
        val rowStride = planes[0].rowStride
        val rowPadding = rowStride - pixelStride * width
        val bitmapWidth = if (rowPadding > 0) width + rowPadding / pixelStride else width
        val bitmap = Bitmap.createBitmap(bitmapWidth, height, Bitmap.Config.ARGB_8888)
        bitmap.copyPixelsFromBuffer(buffer)
        return if (bitmapWidth > width) {
            Bitmap.createBitmap(bitmap, 0, 0, width, height)
        } else {
            bitmap
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

    private fun uploadScreenshot(file: File) {
        serviceScope.launch {
            try {
                val app = applicationContext as? BgApplication ?: return@launch
                RetrofitClient.sessionManager = app.sessionManager
                val deviceId = app.sessionManager.deviceId ?: return@launch
                if (app.sessionManager.token == null) return@launch

                DeviceRepository().uploadScreenshot(deviceId, file)
                file.delete()
            } catch (e: Exception) {
                Log.e(TAG, "Upload failed", e)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(screenshotReceiver)
        } catch (_: Exception) {}
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val TAG = "ScreenshotCapture"
        private const val NOTIFICATION_ID = 100
        const val ACTION_START = "com.bg.ScreenshotCapture.START"
        const val ACTION_CAPTURE = "com.bg.ScreenshotCapture.CAPTURE"
        const val ACTION_CAPTURE_SCREENSHOT = "com.bg.ScreenshotCapture.CAPTURE_SCREENSHOT"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val EXTRA_CAPTURE_IMMEDIATELY = "capture_immediately"
        const val KEY_SCREENSHOT_ENABLED = "screenshot_enabled"

        private val RECEIVER_NOT_EXPORTED
            get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                android.content.Context.RECEIVER_NOT_EXPORTED
            } else {
                0
            }

        fun requestCapture(context: android.content.Context) {
            val intent = Intent(context, ScreenshotCaptureService::class.java).apply {
                action = ACTION_CAPTURE
            }
            context.startService(intent)
        }

        fun sendCaptureBroadcast(context: android.content.Context) {
            val intent = Intent(ACTION_CAPTURE_SCREENSHOT)
            intent.setPackage(context.packageName)
            context.sendBroadcast(intent)
        }

        fun isRunning(context: android.content.Context): Boolean {
            val manager = context.getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            @Suppress("DEPRECATION")
            return manager.getRunningServices(Int.MAX_VALUE).any { it.service.className == ScreenshotCaptureService::class.java.name }
        }
    }
}
