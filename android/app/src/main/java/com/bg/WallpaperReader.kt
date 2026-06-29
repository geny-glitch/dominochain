package com.bg

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Log
import java.io.File
import java.io.FileOutputStream

object WallpaperReader {
    private const val TAG = "WallpaperReader"
    internal const val CACHED_WALLPAPER_FILENAME = "last_set_wallpaper.jpg"

    fun readHomeWallpaper(context: Context): File? {
        return try {
            val wallpaperManager = WallpaperManager.getInstance(context)
            val bitmap = readBitmap(wallpaperManager)
                ?: readCachedWallpaper(context)
                ?: run {
                    Log.e(TAG, "Could not read home wallpaper bitmap or cache")
                    return null
                }
            saveBitmapToFile(context, bitmap)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read wallpaper", e)
            readCachedWallpaperFile(context)
        }
    }

    fun cacheSetWallpaper(context: Context, bitmap: Bitmap) {
        try {
            val file = File(context.cacheDir, CACHED_WALLPAPER_FILENAME)
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            }
            Log.d(TAG, "Cached wallpaper for verification fallback")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to cache wallpaper for verification", e)
        }
    }

    private fun readBitmap(wallpaperManager: WallpaperManager): Bitmap? {
        val drawables = listOfNotNull(
            runCatching { wallpaperManager.getDrawable(WallpaperManager.FLAG_SYSTEM) }.getOrNull(),
            runCatching { wallpaperManager.peekDrawable(WallpaperManager.FLAG_SYSTEM) }.getOrNull(),
            runCatching { wallpaperManager.drawable }.getOrNull()
        )

        for (drawable in drawables) {
            drawableToBitmap(drawable)?.let { return it }
        }
        return null
    }

    private fun readCachedWallpaper(context: Context): Bitmap? {
        val file = File(context.cacheDir, CACHED_WALLPAPER_FILENAME)
        if (!file.exists()) return null
        return runCatching {
            android.graphics.BitmapFactory.decodeFile(file.absolutePath)?.also {
                Log.d(TAG, "Using cached wallpaper fallback for verification")
            }
        }.getOrNull()
    }

    private fun readCachedWallpaperFile(context: Context): File? {
        val file = File(context.cacheDir, CACHED_WALLPAPER_FILENAME)
        return file.takeIf { it.exists() && it.length() > 0 }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return it.copy(it.config ?: Bitmap.Config.ARGB_8888, false) }
        }

        val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 1
        val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 1
        if (width <= 1 || height <= 1) return null

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, width, height)
        drawable.draw(canvas)
        return bitmap
    }

    private fun saveBitmapToFile(context: Context, bitmap: Bitmap): File? {
        return try {
            val file = File(context.cacheDir, "wallpaper_sample_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
            }
            if (!bitmap.isRecycled) bitmap.recycle()
            file
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save wallpaper sample", e)
            null
        }
    }
}
