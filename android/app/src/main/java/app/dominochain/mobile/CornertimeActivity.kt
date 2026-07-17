package app.dominochain.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.cornertime.FrameDiffMotionDetector
import app.dominochain.mobile.cornertime.LumaExtractor
import app.dominochain.mobile.cornertime.MotionDetector
import app.dominochain.mobile.cornertime.PoseMotionDetector
import app.dominochain.mobile.databinding.ActivityCornertimeBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class CornertimeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityCornertimeBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val repository = CornertimeRepository()

    private var cameraExecutor: ExecutorService? = null
    private var sessionId: Long? = null
    private var monitoring = false
    private var calibrating = false
    private var calibrationJob: Job? = null
    private var motionThreshold = 0.12
    private var sanctionCooldownMs = 8_000L
    private var detectionDebounceMs = 1_000L
    private var calibrationMs = 5_000L
    private var violationCount = 0
    private val lastDetectionAt = AtomicLong(0)
    private val lastSanctionAt = AtomicLong(0)
    private val reporting = AtomicBoolean(false)

    private val frameDiffDetector = FrameDiffMotionDetector()
    private var poseDetector: PoseMotionDetector? = null
    private var activeDetector: MotionDetector = frameDiffDetector
    private var usePoseDetection = false

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            startSession()
        } else {
            setHint(getString(R.string.cornertime_camera_denied))
            binding.cornertimeStart.isEnabled = true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = sessionManager
        binding = ActivityCornertimeBinding.inflate(layoutInflater)
        setContentView(binding.root)

        usePoseDetection = intent.getBooleanExtra(EXTRA_USE_POSE, false)

        binding.cornertimeStart.setOnClickListener {
            ensureCameraAndStart()
        }
        binding.cornertimeStop.setOnClickListener {
            stopSession()
        }

        lifecycleScope.launch {
            val config = repository.getConfig().getOrNull()
            if (config?.source_enabled == false) {
                binding.cornertimeStart.isEnabled = false
                setHint(getString(R.string.cornertime_source_disabled))
            }
            applyConfig(config)
        }
    }

    private fun ensureCameraAndStart() {
        when {
            ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED -> startSession()
            else -> cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private fun applyConfig(config: app.dominochain.mobile.api.CornertimeConfigResponse?) {
        if (config == null) return
        config.motion_threshold?.takeIf { it > 0 }?.let { motionThreshold = it }
        config.violation_cooldown_seconds?.takeIf { it > 0 }?.let { sanctionCooldownMs = it * 1000L }
        config.calibration_seconds?.takeIf { it > 0 }?.let { calibrationMs = it * 1000L }
        config.diff_sensitivity?.takeIf { it > 0 }?.let { frameDiffDetector.diffSensitivity = it.toFloat() }
        config.pixel_threshold?.takeIf { it > 0 }?.let { frameDiffDetector.pixelThreshold = it }
        config.cell_active_below?.takeIf { it > 0 }?.let { frameDiffDetector.cellActiveBelow = it }
        config.matrix_width?.takeIf { it > 0 }?.let { frameDiffDetector.matrixWidth = it }
        config.matrix_height?.takeIf { it > 0 }?.let { frameDiffDetector.matrixHeight = it }
    }

    private fun startSession() {
        binding.cornertimeStart.isEnabled = false
        setHint(null)
        setStatus(getString(R.string.cornertime_status_starting))

        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { repository.startSession() }
            result.onSuccess { response ->
                sessionId = response.session.id
                applyConfig(response.config)
                violationCount = 0
                lastDetectionAt.set(0)
                lastSanctionAt.set(0)
                updateViolations()
                bindCamera()
                CornertimeMonitoringService.start(this@CornertimeActivity)
                beginCalibration()
            }.onFailure {
                binding.cornertimeStart.isEnabled = true
                setStatus(getString(R.string.cornertime_status_error))
                setHint(it.message)
            }
        }
    }

    private fun beginCalibration() {
        frameDiffDetector.reset()
        if (usePoseDetection) {
            poseDetector?.close()
            poseDetector = PoseMotionDetector()
            activeDetector = poseDetector ?: frameDiffDetector
        } else {
            poseDetector?.close()
            poseDetector = null
            activeDetector = frameDiffDetector
        }
        activeDetector.reset()
        calibrating = true
        monitoring = true
        binding.cornertimeStop.isEnabled = true
        setStatus(getString(R.string.cornertime_status_calibrating))
        calibrationJob?.cancel()
        calibrationJob = lifecycleScope.launch {
            delay(calibrationMs)
            if (!monitoring) return@launch
            calibrating = false
            setStatus(getString(R.string.cornertime_status_active))
        }
    }

    private fun bindCamera() {
        cameraExecutor?.shutdown()
        cameraExecutor = Executors.newSingleThreadExecutor()
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build().also {
                it.surfaceProvider = binding.cornertimePreview.surfaceProvider
            }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setTargetResolution(android.util.Size(320, 240))
                .build()
            analysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                processFrame(imageProxy)
            }
            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    this,
                    CameraSelector.DEFAULT_FRONT_CAMERA,
                    preview,
                    analysis
                )
            } catch (e: Exception) {
                runOnUiThread {
                    setHint(e.message)
                    setStatus(getString(R.string.cornertime_status_error))
                }
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun processFrame(imageProxy: androidx.camera.core.ImageProxy) {
        if (!monitoring) {
            imageProxy.close()
            return
        }
        val luma = LumaExtractor.fromImageProxy(imageProxy, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
        val pose = poseDetector
        if (pose != null && usePoseDetection) {
            // Pose detector closes the proxy when ML Kit finishes.
            pose.submitImageProxy(imageProxy) {
                evaluateFrame(luma)
            }
            return
        }
        try {
            evaluateFrame(luma)
        } finally {
            imageProxy.close()
        }
    }

    private fun evaluateFrame(luma: FloatArray) {
        if (!monitoring) return
        if (calibrating) {
            activeDetector.onCalibrationFrame(luma, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
            if (activeDetector !== frameDiffDetector) {
                frameDiffDetector.onCalibrationFrame(luma, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
            }
            return
        }
        val score = activeDetector.score(luma, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
            ?: frameDiffDetector.score(luma, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
            ?: return
        if (score > motionThreshold) {
            maybeReportViolation(score.toDouble())
        }
    }

    private fun maybeReportViolation(score: Double) {
        val now = System.currentTimeMillis()
        if (now - lastDetectionAt.get() < detectionDebounceMs) return
        lastDetectionAt.set(now)

        runOnUiThread {
            violationCount += 1
            updateViolations()
        }

        if (!reporting.compareAndSet(false, true)) return
        if (now - lastSanctionAt.get() < sanctionCooldownMs) {
            reporting.set(false)
            return
        }
        lastSanctionAt.set(now)

        val id = sessionId ?: run {
            reporting.set(false)
            return
        }
        lifecycleScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    repository.reportViolation(id, score, UUID.randomUUID().toString())
                }
                result.onSuccess { response ->
                    response.cooldown_remaining_seconds?.let { seconds ->
                        if (seconds > 0) {
                            sanctionCooldownMs = maxOf(detectionDebounceMs, seconds * 1000L)
                        }
                    }
                }
            } finally {
                reporting.set(false)
            }
        }
    }

    private fun stopSession() {
        monitoring = false
        calibrating = false
        calibrationJob?.cancel()
        binding.cornertimeStop.isEnabled = false
        binding.cornertimeStart.isEnabled = true
        setStatus(getString(R.string.cornertime_status_stopped))
        CornertimeMonitoringService.stop(this)
        try {
            ProcessCameraProvider.getInstance(this).get().unbindAll()
        } catch (_: Exception) {
        }
        cameraExecutor?.shutdown()
        cameraExecutor = null
        poseDetector?.close()
        poseDetector = null

        val id = sessionId
        sessionId = null
        if (id != null) {
            lifecycleScope.launch {
                withContext(Dispatchers.IO) { repository.stopSession(id) }
            }
        }
    }

    private fun setStatus(text: String) {
        binding.cornertimeStatus.text = text
    }

    private fun setHint(text: String?) {
        if (text.isNullOrBlank()) {
            binding.cornertimeHint.visibility = View.GONE
            binding.cornertimeHint.text = ""
        } else {
            binding.cornertimeHint.visibility = View.VISIBLE
            binding.cornertimeHint.text = text
        }
    }

    private fun updateViolations() {
        binding.cornertimeViolations.text = getString(R.string.cornertime_violations, violationCount)
    }

    override fun onDestroy() {
        if (monitoring) stopSession()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_USE_POSE = "use_pose"
        private const val ANALYSIS_WIDTH = 160
        private const val ANALYSIS_HEIGHT = 120
    }
}
