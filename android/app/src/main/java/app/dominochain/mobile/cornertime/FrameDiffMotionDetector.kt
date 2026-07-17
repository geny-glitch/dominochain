package app.dominochain.mobile.cornertime

/**
 * Phase 1 motion detection: fraction of pixels that differ from the
 * calibration baseline by more than [pixelDelta].
 *
 * Mean absolute difference dilutes local body motion across the whole frame;
 * a changed-pixel ratio reacts to arm/head movement much more reliably.
 */
class FrameDiffMotionDetector(
    var pixelDelta: Float = DEFAULT_PIXEL_DELTA
) : MotionDetector {
    private var baseline: FloatArray? = null
    private var samples = 0

    override fun reset() {
        baseline = null
        samples = 0
    }

    override fun onCalibrationFrame(luma: FloatArray, width: Int, height: Int) {
        if (luma.average() < 0.02) return
        val current = baseline
        if (current == null || current.size != luma.size) {
            baseline = luma.copyOf()
            samples = 1
            return
        }
        samples += 1
        val n = samples.toFloat()
        for (i in luma.indices) {
            current[i] += (luma[i] - current[i]) / n
        }
    }

    override fun score(luma: FloatArray, width: Int, height: Int): Float? {
        val base = baseline ?: return null
        if (base.size != luma.size || samples < 3) return null
        var changed = 0
        for (i in luma.indices) {
            if (kotlin.math.abs(luma[i] - base[i]) > pixelDelta) changed += 1
        }
        return changed.toFloat() / luma.size
    }

    companion object {
        const val DEFAULT_PIXEL_DELTA = 0.10f
    }
}
