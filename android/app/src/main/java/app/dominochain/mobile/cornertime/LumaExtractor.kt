package app.dominochain.mobile.cornertime

import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer

object LumaExtractor {
    fun fromImageProxy(image: ImageProxy, targetWidth: Int = 160, targetHeight: Int = 120): FloatArray {
        val yPlane = image.planes[0]
        val buffer: ByteBuffer = yPlane.buffer
        val rowStride = yPlane.rowStride
        val pixelStride = yPlane.pixelStride
        val srcWidth = image.width
        val srcHeight = image.height
        val out = FloatArray(targetWidth * targetHeight)

        for (y in 0 until targetHeight) {
            val srcY = (y * srcHeight) / targetHeight
            for (x in 0 until targetWidth) {
                val srcX = (x * srcWidth) / targetWidth
                val index = srcY * rowStride + srcX * pixelStride
                val value = if (index < buffer.capacity()) {
                    (buffer.get(index).toInt() and 0xFF) / 255f
                } else {
                    0f
                }
                out[y * targetWidth + x] = value
            }
        }
        return out
    }
}
