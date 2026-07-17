package app.dominochain.mobile.cornertime

/**
 * Dual motion detector:
 * 1) Diffy consecutive-frame score (instant movement)
 * 2) Pose drift vs calibration baseline (slow crawl / leaving frame)
 *
 * Drift must stay above [driftThreshold] for [driftHoldMs] so brief
 * rebalancing does not trigger, but a slow full move does.
 * After a drift trigger, call [rebaseBaseline] so staying put does not
 * keep firing until the original pose is restored.
 */
class FrameDiffMotionDetector(
    var diffSensitivity: Float = 0.2f,
    var pixelThreshold: Int = 21,
    var cellActiveBelow: Int = 200,
    var matrixWidth: Int = 12,
    var matrixHeight: Int = 8,
    var motionThreshold: Float = 0.12f,
    var driftThreshold: Float = 0.18f,
    var driftHoldMs: Long = 1800L,
    var driftPixelDelta: Float = 18f
) : MotionDetector {
    enum class TriggerKind { NONE, INSTANT, DRIFT }

    data class Evaluation(
        val shouldTrigger: Boolean,
        val score: Float,
        val kind: TriggerKind = TriggerKind.NONE
    )

    private var previous: FloatArray? = null
    private var baseline: FloatArray? = null
    private var baselineSamples = 0
    private var width = 0
    private var height = 0
    private var driftSinceMs: Long? = null

    override fun reset() {
        previous = null
        baseline = null
        baselineSamples = 0
        driftSinceMs = null
    }

    override fun onCalibrationFrame(luma: FloatArray, width: Int, height: Int) {
        this.width = width
        this.height = height
        previous = luma.copyOf()
        accumulateBaseline(luma)
    }

    override fun score(luma: FloatArray, width: Int, height: Int): Float? {
        return evaluate(luma, width, height).score.takeIf { it > 0f }
    }

    fun evaluate(
        luma: FloatArray,
        width: Int,
        height: Int,
        nowMs: Long = System.currentTimeMillis()
    ): Evaluation {
        this.width = width
        this.height = height
        val instant = instantScore(luma) ?: 0f
        if (instant > motionThreshold) {
            return Evaluation(shouldTrigger = true, score = instant, kind = TriggerKind.INSTANT)
        }
        val drift = driftEvaluate(luma, nowMs)
        if (drift.triggered) {
            return Evaluation(shouldTrigger = true, score = drift.score, kind = TriggerKind.DRIFT)
        }
        return Evaluation(shouldTrigger = false, score = maxOf(instant, drift.score))
    }

    /** Re-anchor drift baseline to the current frame after a drift sanction. */
    fun rebaseBaseline(luma: FloatArray) {
        baseline = luma.copyOf()
        baselineSamples = maxOf(baselineSamples, 8)
        driftSinceMs = null
    }

    private fun accumulateBaseline(luma: FloatArray) {
        val current = baseline
        if (current == null || current.size != luma.size) {
            baseline = luma.copyOf()
            baselineSamples = 1
            return
        }
        baselineSamples += 1
        val n = baselineSamples.toFloat()
        for (i in luma.indices) {
            current[i] += (luma[i] - current[i]) / n
        }
    }

    private fun instantScore(luma: FloatArray): Float? {
        val prev = previous
        if (prev == null || prev.size != luma.size) {
            previous = luma.copyOf()
            return null
        }

        val amp = (1f - diffSensitivity).coerceAtLeast(0.05f)
        val diff = ByteArray(luma.size)
        for (i in luma.indices) {
            val c = Math.round(luma[i] * 255f / amp)
            val p = Math.round(prev[i] * 255f / amp)
            val delta = kotlin.math.abs(c - p)
            diff[i] = if (delta > pixelThreshold) 0 else 255.toByte()
        }
        previous = luma.copyOf()

        return matrixActiveFraction(diff)
    }

    private data class DriftResult(val score: Float, val triggered: Boolean)

    private fun driftEvaluate(luma: FloatArray, nowMs: Long): DriftResult {
        val base = baseline
        if (base == null || baselineSamples < 3 || base.size != luma.size) {
            return DriftResult(0f, false)
        }

        val cellW = width.toFloat() / matrixWidth
        val cellH = height.toFloat() / matrixHeight
        var drifted = 0
        val total = matrixWidth * matrixHeight
        for (row in 0 until matrixHeight) {
            for (col in 0 until matrixWidth) {
                val x0 = (col * cellW).toInt()
                val y0 = (row * cellH).toInt()
                val x1 = ((col + 1) * cellW).toInt().coerceAtMost(width)
                val y1 = ((row + 1) * cellH).toInt().coerceAtMost(height)
                val cur = cellMean(luma, width, x0, y0, x1, y1) * 255f
                val ref = cellMean(base, width, x0, y0, x1, y1) * 255f
                if (kotlin.math.abs(cur - ref) > driftPixelDelta) drifted += 1
            }
        }
        val score = if (total > 0) drifted.toFloat() / total else 0f
        if (score > driftThreshold) {
            val since = driftSinceMs
            if (since == null) {
                driftSinceMs = nowMs
                return DriftResult(score, false)
            }
            return DriftResult(score, nowMs - since >= driftHoldMs)
        }
        driftSinceMs = null
        return DriftResult(score, false)
    }

    private fun matrixActiveFraction(diff: ByteArray): Float {
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
                if (cellAverageBytes(diff, width, x0, y0, x1, y1) < cellActiveBelow) {
                    active += 1
                }
            }
        }
        return if (total > 0) active.toFloat() / total else 0f
    }

    private fun cellMean(
        buf: FloatArray,
        stride: Int,
        x0: Int,
        y0: Int,
        x1: Int,
        y1: Int
    ): Float {
        var sum = 0f
        var count = 0
        for (y in y0 until y1) {
            val row = y * stride
            for (x in x0 until x1) {
                sum += buf[row + x]
                count += 1
            }
        }
        return if (count > 0) sum / count else 0f
    }

    private fun cellAverageBytes(
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
