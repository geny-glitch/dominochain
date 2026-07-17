package app.dominochain.mobile.cornertime

import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import kotlin.math.hypot
import kotlin.math.min
import java.util.concurrent.atomic.AtomicReference

/**
 * Phase 2 motion detection: compares key body landmarks against a calibrated pose.
 * Processes frames asynchronously; [score] uses the latest completed pose.
 */
class PoseMotionDetector : MotionDetector {
    private val detector: PoseDetector = PoseDetection.getClient(
        PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
            .build()
    )

    private var baseline: Map<Int, Pair<Float, Float>>? = null
    private var samples = 0
    private val latestLandmarks = AtomicReference<Map<Int, Pair<Float, Float>>?>(null)
    private val processing = AtomicReference(false)
    private var frameWidth = 1
    private var frameHeight = 1

    override fun reset() {
        baseline = null
        samples = 0
        latestLandmarks.set(null)
    }

    /** Submit a camera frame for async pose detection. Closes [imageProxy] when done. */
    fun submitImageProxy(imageProxy: ImageProxy, onDone: () -> Unit = {}) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            onDone()
            return
        }
        if (!processing.compareAndSet(false, true)) {
            imageProxy.close()
            onDone()
            return
        }
        frameWidth = imageProxy.width
        frameHeight = imageProxy.height
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        detector.process(image)
            .addOnSuccessListener { pose ->
                latestLandmarks.set(extractLandmarks(pose))
                processing.set(false)
                imageProxy.close()
                onDone()
            }
            .addOnFailureListener {
                processing.set(false)
                imageProxy.close()
                onDone()
            }
    }

    override fun onCalibrationFrame(luma: FloatArray, width: Int, height: Int) {
        val landmarks = latestLandmarks.get() ?: return
        val current = baseline
        if (current == null) {
            baseline = landmarks
            samples = 1
            return
        }
        samples += 1
        val n = samples.toFloat()
        val merged = current.toMutableMap()
        landmarks.forEach { (id, point) ->
            val prev = merged[id]
            if (prev == null) {
                merged[id] = point
            } else {
                merged[id] = Pair(
                    prev.first + (point.first - prev.first) / n,
                    prev.second + (point.second - prev.second) / n
                )
            }
        }
        baseline = merged
    }

    override fun score(luma: FloatArray, width: Int, height: Int): Float? {
        val base = baseline ?: return null
        val landmarks = latestLandmarks.get() ?: return null
        if (landmarks.isEmpty() || base.isEmpty()) return null

        var sum = 0f
        var count = 0
        val diag = hypot(frameWidth.toFloat(), frameHeight.toFloat()).coerceAtLeast(1f)
        landmarks.forEach { (id, point) ->
            val ref = base[id] ?: return@forEach
            val dist = hypot(point.first - ref.first, point.second - ref.second)
            sum += dist / diag
            count += 1
        }
        if (count == 0) return null
        return min(1f, sum / count)
    }

    fun close() {
        detector.close()
    }

    private fun extractLandmarks(pose: Pose): Map<Int, Pair<Float, Float>>? {
        val ids = listOf(
            PoseLandmark.LEFT_SHOULDER,
            PoseLandmark.RIGHT_SHOULDER,
            PoseLandmark.LEFT_HIP,
            PoseLandmark.RIGHT_HIP,
            PoseLandmark.NOSE
        )
        val map = mutableMapOf<Int, Pair<Float, Float>>()
        ids.forEach { id ->
            val landmark = pose.getPoseLandmark(id) ?: return@forEach
            if (landmark.inFrameLikelihood < 0.5f) return@forEach
            map[id] = Pair(landmark.position.x, landmark.position.y)
        }
        return map.takeIf { it.size >= 3 }
    }
}
