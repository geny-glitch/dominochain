package com.bg

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream

object WallpaperReader {
    private const val TAG = "WallpaperReader"

    fun readHomeWallpaper(context: Context): File? {
        return try {
            val wallpaperManager = WallpaperManager.getInstance(context)
            val bitmap = readBitmap(wallpaperManager) ?: run {
                Log.e(TAG, "Could not read home wallpaper bitmap")
                return null
            }
            saveBitmapToFile(context, bitmap)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read wallpaper", e)
            null
        }
    }

    private fun readBitmap(wallpaperManager: WallpaperManager): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            wallpaperManager.getBitmap()?.let { return it }
        }

        val drawable = wallpaperManager.drawable ?: return null
        if (drawable is BitmapDrawable) {
            drawable.bitmap?.let { return it }
        }

        val width = drawable.intrinsicWidth.coerceAtLeast(1)
        val height = drawable.intrinsicHeight.coerceAtLeast(1)
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
