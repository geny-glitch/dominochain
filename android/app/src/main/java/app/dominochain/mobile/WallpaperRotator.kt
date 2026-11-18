package app.dominochain.mobile

import android.annotation.SuppressLint
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.util.Log
import app.dominochain.mobile.api.WallpaperRotationPayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max

/**
 * Local background rotation. Slot math matches WallpaperRotations::Schedule:
 * collage when slot % 5 == 4, 4 photos on even slots when at least 4 are selected,
 * otherwise 2, walking forward from the slot.
 */
object WallpaperRotator {
    private const val TAG = "WallpaperRotator"
    private const val KEY_ACTIVE = "wallpaper_rotation_active"
    private const val DIR_NAME = "wallpaper_rotation"
    private const val PLAN_FILE = "plan.json"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val applyLock = Any()

    @Volatile private var plan: Plan? = null
    @Volatile private var lastAppliedKey: String? = null
    private var loopJob: kotlinx.coroutines.Job? = null
    private var receiverRegistered = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != Intent.ACTION_SCREEN_ON) return
            val app = context.applicationContext
            scope.launch {
                lastAppliedKey = null
                plan?.let { apply(app, it) }
            }
        }
    }

    fun isActive(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_ACTIVE, false)
    }

    fun resume(context: Context) {
        val app = context.applicationContext
        if (!isActive(app)) return
        scope.launch {
            val loaded = load(app) ?: return@launch
            plan = loaded
            startLoop(app)
            apply(app, loaded)
        }
    }

    suspend fun install(context: Context, payload: WallpaperRotationPayload): Boolean = withContext(Dispatchers.IO) {
        val app = context.applicationContext
        if (!payload.enabled || payload.images.size < 2 || payload.interval_seconds <= 0) {
            return@withContext false
        }
        val anchor = try {
            java.time.OffsetDateTime.parse(payload.anchor_at).toEpochSecond()
        } catch (e: Exception) {
            Log.e(TAG, "Invalid rotation anchor", e)
            return@withContext false
        }

        val existing = plan ?: load(app)
        if (existing != null && existing.revision == payload.revision && existing.images.size == payload.images.size) {
            plan = existing
            prefs(app).edit().putBoolean(KEY_ACTIVE, true).apply()
            startLoop(app)
            apply(app, existing)
            return@withContext true
        }

        val folder = directory(app)
        val downloaded = mutableListOf<ImageFile>()
        for (image in payload.images) {
            val dest = File(folder, "img_${image.id}.img")
            val temp = File(folder, "img_${image.id}.img.tmp")
            if (!download(image.url, temp)) {
                temp.delete()
                return@withContext false
            }
            if (!temp.renameTo(dest)) {
                temp.copyTo(dest, overwrite = true)
                temp.delete()
            }
            downloaded += ImageFile(image.id, dest)
        }

        val keep = downloaded.map { it.file.name }.toSet() + PLAN_FILE
        folder.listFiles()?.forEach { file ->
            if (file.name !in keep && !file.name.endsWith(".tmp")) file.delete()
        }

        val next = Plan(
            revision = payload.revision,
            intervalSeconds = payload.interval_seconds.toLong(),
            collages = payload.collages,
            anchorEpochSeconds = anchor,
            canvasWidth = payload.canvas_width,
            canvasHeight = payload.canvas_height,
            images = downloaded
        )
        persist(app, next)
        plan = next
        lastAppliedKey = null
        prefs(app).edit().putBoolean(KEY_ACTIVE, true).apply()
        startLoop(app)
        apply(app, next)
        true
    }

    fun clear(context: Context) {
        val app = context.applicationContext
        synchronized(applyLock) {
            plan = null
            lastAppliedKey = null
            loopJob?.cancel()
            loopJob = null
        }
        prefs(app).edit().putBoolean(KEY_ACTIVE, false).apply()
        directory(app).deleteRecursively()
    }

    private fun startLoop(context: Context) {
        ensureScreenReceiver(context)
        if (loopJob?.isActive == true) return
        val app = context.applicationContext
        loopJob = scope.launch {
            while (isActive) {
                val current = plan ?: break
                try {
                    apply(app, current)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to apply rotation", e)
                }
                delay(current.millisUntilNext())
            }
        }
    }

    private fun apply(context: Context, current: Plan) {
        synchronized(applyLock) {
            val active = plan
            if (active != null && active.revision != current.revision) return
            if (active == null) return
            val slot = current.slotAt(System.currentTimeMillis())
            val key = "${current.revision}:$slot"
            if (key == lastAppliedKey) return
            val indexes = current.indexes(slot)
            if (indexes.isEmpty()) return
            val bitmaps = indexes.mapNotNull { index ->
                BitmapFactory.decodeFile(current.images[index].file.absolutePath)
            }
            if (bitmaps.size != indexes.size) {
                bitmaps.forEach { if (!it.isRecycled) it.recycle() }
                return
            }
            var composed: Bitmap? = null
            try {
                val output = if (bitmaps.size == 1) {
                    bitmaps[0]
                } else {
                    compose(bitmaps, current.canvasWidth, current.canvasHeight).also { composed = it }
                }
                WallpaperManager.getInstance(context).setBitmap(output)
                lastAppliedKey = key
                Log.d(TAG, "Applied rotation slot=$slot parts=${bitmaps.size}")
            } catch (e: Exception) {
                Log.e(TAG, "setBitmap failed", e)
            } finally {
                composed?.let { if (!it.isRecycled) it.recycle() }
                bitmaps.forEach { if (!it.isRecycled) it.recycle() }
            }
        }
    }

    private fun compose(bitmaps: List<Bitmap>, canvasWidth: Int, canvasHeight: Int): Bitmap {
        var width = canvasWidth
        var height = canvasHeight
        if (width <= 1 || height <= 1) {
            width = bitmaps[0].width
            height = bitmaps[0].height
        }
        if (width % 2 != 0) width -= 1
        if (height % 2 != 0) height -= 1
        if (width < 2) width = 2
        if (height < 2) height = 2
        val output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        if (bitmaps.size >= 4) {
            val halfW = width / 2
            val halfH = height / 2
            drawCover(canvas, bitmaps[0], Rect(0, 0, halfW, halfH))
            drawCover(canvas, bitmaps[1], Rect(halfW, 0, width, halfH))
            drawCover(canvas, bitmaps[2], Rect(0, halfH, halfW, height))
            drawCover(canvas, bitmaps[3], Rect(halfW, halfH, width, height))
        } else {
            val halfW = width / 2
            drawCover(canvas, bitmaps[0], Rect(0, 0, halfW, height))
            drawCover(canvas, bitmaps[1], Rect(halfW, 0, width, height))
        }
        return output
    }

    private fun drawCover(canvas: Canvas, bitmap: Bitmap, dest: Rect) {
        val bitmapWidth = bitmap.width.toFloat()
        val bitmapHeight = bitmap.height.toFloat()
        val destWidth = dest.width().toFloat()
        val destHeight = dest.height().toFloat()
        if (bitmapWidth <= 0f || bitmapHeight <= 0f || destWidth <= 0f || destHeight <= 0f) return
        val scale = max(destWidth / bitmapWidth, destHeight / bitmapHeight)
        val scaledWidth = bitmapWidth * scale
        val scaledHeight = bitmapHeight * scale
        val left = dest.left + (destWidth - scaledWidth) / 2f
        val top = dest.top + (destHeight - scaledHeight) / 2f
        val source = Rect(0, 0, bitmap.width, bitmap.height)
        val target = RectF(left, top, left + scaledWidth, top + scaledHeight)
        canvas.save()
        canvas.clipRect(dest)
        canvas.drawBitmap(bitmap, source, target, Paint(Paint.FILTER_BITMAP_FLAG))
        canvas.restore()
    }

    private fun download(urlString: String, dest: File): Boolean {
        return try {
            val connection = URL(urlString).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.connect()
            if (connection.responseCode !in 200..299) {
                connection.disconnect()
                return false
            }
            connection.inputStream.use { input ->
                FileOutputStream(dest).use { output -> input.copyTo(output) }
            }
            connection.disconnect()
            dest.length() > 0
        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            false
        }
    }

    private fun persist(context: Context, current: Plan) {
        val images = JSONArray()
        current.images.forEach { image ->
            images.put(JSONObject().put("id", image.id).put("file", image.file.name))
        }
        val json = JSONObject()
            .put("revision", current.revision)
            .put("intervalSeconds", current.intervalSeconds)
            .put("collages", current.collages)
            .put("anchorEpochSeconds", current.anchorEpochSeconds)
            .put("canvasWidth", current.canvasWidth)
            .put("canvasHeight", current.canvasHeight)
            .put("images", images)
        File(directory(context), PLAN_FILE).writeText(json.toString())
    }

    private fun load(context: Context): Plan? {
        val file = File(directory(context), PLAN_FILE)
        if (!file.exists()) return null
        return try {
            val json = JSONObject(file.readText())
            val imagesJson = json.getJSONArray("images")
            val images = (0 until imagesJson.length()).map { index ->
                val item = imagesJson.getJSONObject(index)
                val imageFile = File(directory(context), item.getString("file"))
                if (!imageFile.exists()) return null
                ImageFile(item.getLong("id"), imageFile)
            }
            if (images.size < 2) return null
            Plan(
                revision = json.getString("revision"),
                intervalSeconds = json.getLong("intervalSeconds"),
                collages = json.getBoolean("collages"),
                anchorEpochSeconds = json.getLong("anchorEpochSeconds"),
                canvasWidth = json.getInt("canvasWidth"),
                canvasHeight = json.getInt("canvasHeight"),
                images = images
            )
        } catch (e: Exception) {
            Log.e(TAG, "Could not read rotation plan", e)
            null
        }
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun ensureScreenReceiver(context: Context) {
        if (receiverRegistered) return
        val app = context.applicationContext
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(screenReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun directory(context: Context): File {
        return File(context.filesDir, DIR_NAME).apply { mkdirs() }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(WallpaperWorker.PREFS_NAME, Context.MODE_PRIVATE)

    private data class ImageFile(val id: Long, val file: File)

    private data class Plan(
        val revision: String,
        val intervalSeconds: Long,
        val collages: Boolean,
        val anchorEpochSeconds: Long,
        val canvasWidth: Int,
        val canvasHeight: Int,
        val images: List<ImageFile>
    ) {
        fun slotAt(nowMillis: Long): Long {
            if (intervalSeconds <= 0L) return 0L
            val elapsed = (nowMillis / 1000L - anchorEpochSeconds).coerceAtLeast(0L)
            return elapsed / intervalSeconds
        }

        fun indexes(slot: Long): List<Int> {
            val count = images.size
            if (count == 0) return emptyList()
            val total = count.toLong()
            val collage = collages && count >= 2 && (slot % 5L) == 4L
            if (!collage) return listOf((slot % total).toInt())
            val cells = if (count >= 4 && slot % 2L == 0L) 4 else 2
            return (0 until cells).map { offset -> ((slot + offset) % total).toInt() }
        }

        fun millisUntilNext(nowMillis: Long = System.currentTimeMillis()): Long {
            val intervalMs = intervalSeconds * 1000L
            if (intervalMs <= 0L) return 30_000L
            val elapsed = nowMillis - anchorEpochSeconds * 1000L
            if (elapsed < 0L) return (-elapsed).coerceAtLeast(250L)
            val into = elapsed % intervalMs
            return (intervalMs - into).coerceIn(250L, intervalMs)
        }
    }
}
