package app.dominochain.mobile.cornertime

/**
 * Diffy-style consecutive-frame motion detection.
 *
 * Ported from https://github.com/maniart/diffyjs (MIT):
 * blend current vs previous frame with contrast amplification, threshold to
 * a binary motion map, then average into a coarse matrix. Score = fraction of
 * cells that contain enough motion.
 */
class FrameDiffMotionDetector(
    var diffSensitivity: Float = 0.2f,
    var pixelThreshold: Int = 21,
    var cellActiveBelow: Int = 200,
    var matrixWidth: Int = 12,
    var matrixHeight: Int = 8
) : MotionDetector {
    private var previous: FloatArray? = null
    private var width = 0
    private var height = 0
    private var readyFrames = 0

    override fun reset() {
        previous = null
        readyFrames = 0
    }

    override fun onCalibrationFrame(luma: FloatArray, width: Int, height: Int) {
        // During warm-up, just seed the previous frame buffer.
        this.width = width
        this.height = height
        previous = luma.copyOf()
        readyFrames = 1
    }

    override fun score(luma: FloatArray, width: Int, height: Int): Float? {
        this.width = width
        this.height = height
        val prev = previous
        if (prev == null || prev.size != luma.size) {
            previous = luma.copyOf()
            readyFrames = 1
            return null
        }
        readyFrames += 1
        if (readyFrames < 2) {
            previous = luma.copyOf()
            return null
        }

        val amp = (1f - diffSensitivity).coerceAtLeast(0.05f)
        val diff = ByteArray(luma.size)
        for (i in luma.indices) {
            val c = Math.round(luma[i] * 255f / amp)
            val p = Math.round(prev[i] * 255f / amp)
            val delta = kotlin.math.abs(c - p)
            // Diffy encoding: motion → 0, still → 255
            diff[i] = if (delta > pixelThreshold) 0 else 255.toByte()
        }
        previous = luma.copyOf()

        val cellW = width.toFloat() / matrixWidth
        val cellH = height.toFloat() / matrixHeight
        var active = 0
        val total = matrixWidth * matrixHeight
        for (row in 0 until matrixHeight) {
            for (col in 0 until matrixWidth) {
                val x0 = (col * cellW).toInt()
                val y0 = (row * cellH).toInt()
                val x1 = ((col + 1) * cellW).toInt().coerceAtMost(width)
                val y1 = ((row + 1) * cellH).toInt().coerceAtMost(height)
                if (cellAverage(diff, width, x0, y0, x1, y1) < cellActiveBelow) {
                    active += 1
                }
            }
        }
        return if (total > 0) active.toFloat() / total else 0f
    }

    private fun cellAverage(
        diff: ByteArray,
        stride: Int,
        x0: Int,
        y0: Int,
        x1: Int,
        y1: Int
    ): Int {
        var sum = 0
        var count = 0
        for (y in y0 until y1) {
            val row = y * stride
            for (x in x0 until x1) {
                sum += (diff[row + x].toInt() and 0xFF)
                count += 1
            }
        }
        return if (count > 0) sum / count else 255
    }
}
