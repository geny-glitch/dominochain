package app.dominochain.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
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
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.regex.Pattern

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
    private var driftThreshold = 0.18
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
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var voiceLocaleTag = "fr"
    private var voiceIntro: String = ""
    private var voiceStopMoving: String = ""
    private var voiceReturnToPosition: String = ""
    private var availableVoices: List<Voice> = emptyList()
    private var selectedVoiceName: String? = null
    private var voicePickerReady = false
    private var durationOptions: List<Int> = DEFAULT_DURATIONS_MINUTES
    private var sessionEndsAtMs: Long? = null
    private var remainingJob: Job? = null
    private var finishing = false

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
        voiceIntro = getString(R.string.cornertime_voice_intro)
        voiceStopMoving = getString(R.string.cornertime_voice_stop_moving)
        voiceReturnToPosition = getString(R.string.cornertime_voice_return_to_position)
        selectedVoiceName = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getString(PREF_VOICE_NAME, null)
        setupDurationPicker(durationOptions)
        initTts()
        binding.cornertimeVoice.setOnCheckedChangeListener { _, checked ->
            binding.cornertimeVoicePick.visibility = if (checked) View.VISIBLE else View.GONE
            binding.cornertimeVoicePickLabel.visibility = if (checked) View.VISIBLE else View.GONE
        }

        binding.cornertimeStart.setOnClickListener {
            ensureCameraAndStart()
        }
        binding.cornertimeStop.setOnClickListener {
            stopSession(autoComplete = false)
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
        config.motion_threshold?.takeIf { it > 0 }?.let {
            motionThreshold = it
            frameDiffDetector.motionThreshold = it.toFloat()
        }
        config.drift_threshold?.takeIf { it > 0 }?.let { driftThreshold = it }
        config.violation_cooldown_seconds?.takeIf { it > 0 }?.let { sanctionCooldownMs = it * 1000L }
        config.calibration_seconds?.takeIf { it > 0 }?.let { calibrationMs = it * 1000L }
        config.diff_sensitivity?.takeIf { it > 0 }?.let { frameDiffDetector.diffSensitivity = it.toFloat() }
        config.pixel_threshold?.takeIf { it > 0 }?.let { frameDiffDetector.pixelThreshold = it }
        config.cell_active_below?.takeIf { it > 0 }?.let { frameDiffDetector.cellActiveBelow = it }
        config.matrix_width?.takeIf { it > 0 }?.let { frameDiffDetector.matrixWidth = it }
        config.matrix_height?.takeIf { it > 0 }?.let { frameDiffDetector.matrixHeight = it }
        config.drift_threshold?.takeIf { it > 0 }?.let { frameDiffDetector.driftThreshold = it.toFloat() }
        config.drift_hold_ms?.takeIf { it > 0 }?.let { frameDiffDetector.driftHoldMs = it.toLong() }
        config.drift_pixel_delta?.takeIf { it > 0 }?.let { frameDiffDetector.driftPixelDelta = it.toFloat() }
        config.allowed_durations_minutes
            ?.mapNotNull { it.takeIf { minutes -> minutes > 0 } }
            ?.takeIf { it.isNotEmpty() }
            ?.let {
                durationOptions = it
                setupDurationPicker(it)
            }
        applyVoiceFromConfig(config)
    }

    private fun setupDurationPicker(minutesOptions: List<Int>) {
        val labels = minutesOptions.map { getString(R.string.cornertime_duration_option, it) }
        binding.cornertimeDuration.adapter =
            ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        val saved = prefs.getInt(PREF_DURATION_MINUTES, minutesOptions.firstOrNull() ?: 10)
        val index = minutesOptions.indexOf(saved).takeIf { it >= 0 }
            ?: minutesOptions.indexOf(10).takeIf { it >= 0 }
            ?: 0
        binding.cornertimeDuration.setSelection(index)
        binding.cornertimeDuration.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val minutes = durationOptions.getOrNull(position) ?: return
                prefs.edit().putInt(PREF_DURATION_MINUTES, minutes).apply()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
    }

    private fun selectedDurationMinutes(): Int? {
        return durationOptions.getOrNull(binding.cornertimeDuration.selectedItemPosition)
    }

    private fun applyVoiceFromConfig(config: app.dominochain.mobile.api.CornertimeConfigResponse) {
        config.locale?.takeIf { it.isNotBlank() }?.let { tag ->
            voiceLocaleTag = tag.replace('_', '-')
            applyTtsLanguage()
        }
        config.voice?.let { voice ->
            voice.intro?.takeIf { it.isNotBlank() }?.let { voiceIntro = it }
            voice.stop_moving?.takeIf { it.isNotBlank() }?.let { voiceStopMoving = it }
            voice.return_to_position?.takeIf { it.isNotBlank() }?.let { voiceReturnToPosition = it }
        }
    }

    private fun startSession() {
        val durationMinutes = selectedDurationMinutes()
        if (durationMinutes == null) {
            setHint(getString(R.string.cornertime_duration_required))
            return
        }
        binding.cornertimeStart.isEnabled = false
        binding.cornertimeDuration.isEnabled = false
        setHint(null)
        setStatus(getString(R.string.cornertime_status_starting))

        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) { repository.startSession(durationMinutes) }
            result.onSuccess { response ->
                sessionId = response.session.id
                applyConfig(response.config)
                violationCount = 0
                lastDetectionAt.set(0)
                lastSanctionAt.set(0)
                updateViolations()
                sessionEndsAtMs = response.session.ends_at?.let { parseIsoMillis(it) }
                    ?: response.session.planned_duration_seconds?.let {
                        System.currentTimeMillis() + it * 1000L
                    }
                startRemainingTicker()
                bindCamera()
                CornertimeMonitoringService.start(this@CornertimeActivity)
                beginCalibration()
            }.onFailure {
                binding.cornertimeStart.isEnabled = true
                binding.cornertimeDuration.isEnabled = true
                setStatus(getString(R.string.cornertime_status_error))
                setHint(it.message)
            }
        }
    }

    private fun parseIsoMillis(value: String): Long? {
        return try {
            java.time.Instant.parse(value).toEpochMilli()
        } catch (_: Exception) {
            null
        }
    }

    private fun startRemainingTicker() {
        remainingJob?.cancel()
        remainingJob = lifecycleScope.launch {
            while (monitoring || calibrating || sessionId != null) {
                val endsAt = sessionEndsAtMs
                if (endsAt == null) {
                    binding.cornertimeRemaining.visibility = View.GONE
                } else {
                    val leftMs = endsAt - System.currentTimeMillis()
                    binding.cornertimeRemaining.visibility = View.VISIBLE
                    binding.cornertimeRemaining.text =
                        getString(R.string.cornertime_remaining, formatDuration(leftMs))
                    if (leftMs <= 0L && !finishing) {
                        stopSession(autoComplete = true)
                        break
                    }
                }
                delay(1000)
            }
        }
    }

    private fun formatDuration(ms: Long): String {
        val total = maxOf(0, ms / 1000).toInt()
        val m = total / 60
        val s = total % 60
        return "%02d:%02d".format(m, s)
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
            speak(voiceIntro)
        }
    }

    private fun initTts() {
        tts = TextToSpeech(this) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                runOnUiThread { applyTtsLanguage() }
            }
        }
    }

    private fun applyTtsLanguage() {
        if (!ttsReady) return
        val locale = Locale.forLanguageTag(voiceLocaleTag)
        val result = tts?.setLanguage(locale)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            tts?.language = Locale.forLanguageTag(voiceLocaleTag.take(2))
        }
        refreshVoicePicker()
        applySelectedVoice()
    }

    private fun voicesForLocale(): List<Voice> {
        val engine = tts ?: return emptyList()
        val all = engine.voices ?: return emptyList()
        val wanted = voiceLocaleTag.lowercase(Locale.ROOT)
        val prefix = wanted.take(2)
        val exact = all.filter { it.locale.toLanguageTag().lowercase(Locale.ROOT) == wanted }
        if (exact.isNotEmpty()) return exact.sortedWith(voiceComparator())
        return all
            .filter { it.locale.language.lowercase(Locale.ROOT) == prefix }
            .sortedWith(voiceComparator())
    }

    private fun voiceComparator(): Comparator<Voice> {
        return Comparator { a, b ->
            val af = if (isFemaleVoice(a.name)) 0 else 1
            val bf = if (isFemaleVoice(b.name)) 0 else 1
            if (af != bf) af - bf else a.name.compareTo(b.name, ignoreCase = true)
        }
    }

    private fun isFemaleVoice(name: String): Boolean {
        if (MALE_VOICE_RE.matcher(name).find()) return false
        return FEMALE_VOICE_RE.matcher(name).find()
    }

    private fun preferredVoice(voices: List<Voice>): Voice? {
        if (voices.isEmpty()) return null
        selectedVoiceName?.let { saved ->
            voices.find { it.name == saved }?.let { return it }
        }
        return voices.find { isFemaleVoice(it.name) } ?: voices.first()
    }

    private fun refreshVoicePicker() {
        availableVoices = voicesForLocale()
        val labels = availableVoices.map { voice ->
            if (isFemaleVoice(voice.name)) "${voice.name} ♀" else voice.name
        }
        val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
        binding.cornertimeVoicePick.adapter = adapter
        val preferred = preferredVoice(availableVoices)
        val index = preferred?.let { availableVoices.indexOf(it) } ?: -1
        voicePickerReady = false
        if (index >= 0) binding.cornertimeVoicePick.setSelection(index)
        binding.cornertimeVoicePick.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (!voicePickerReady) {
                    voicePickerReady = true
                    return
                }
                val voice = availableVoices.getOrNull(position) ?: return
                selectedVoiceName = voice.name
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putString(PREF_VOICE_NAME, voice.name)
                    .apply()
                applySelectedVoice()
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
        voicePickerReady = true
        val checked = binding.cornertimeVoice.isChecked
        binding.cornertimeVoicePick.visibility = if (checked && availableVoices.isNotEmpty()) View.VISIBLE else View.GONE
        binding.cornertimeVoicePickLabel.visibility =
            if (checked && availableVoices.isNotEmpty()) View.VISIBLE else View.GONE
    }

    private fun applySelectedVoice() {
        val voice = preferredVoice(availableVoices) ?: return
        selectedVoiceName = voice.name
        tts?.voice = voice
    }

    private fun voiceEnabled(): Boolean {
        return binding.cornertimeVoice.isChecked && ttsReady
    }

    private fun speak(text: String) {
        if (!voiceEnabled() || text.isBlank()) return
        applySelectedVoice()
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "cornertime-${System.currentTimeMillis()}")
    }

    private fun stopSpeaking() {
        tts?.stop()
    }

    private fun bindCamera() {
        cameraExecutor?.shutdown()
        cameraExecutor = Executors.newSingleThreadExecutor()
        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(binding.cornertimePreview.surfaceProvider)
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
        val result = frameDiffDetector.evaluate(luma, ANALYSIS_WIDTH, ANALYSIS_HEIGHT)
        if (result.shouldTrigger) {
            maybeReportViolation(result.score.toDouble(), result.kind, luma)
        }
    }

    private fun maybeReportViolation(
        score: Double,
        kind: FrameDiffMotionDetector.TriggerKind,
        luma: FloatArray
    ) {
        val now = System.currentTimeMillis()
        if (now - lastDetectionAt.get() < detectionDebounceMs) return
        lastDetectionAt.set(now)

        if (kind == FrameDiffMotionDetector.TriggerKind.DRIFT) {
            frameDiffDetector.rebaseBaseline(luma)
        }

        runOnUiThread {
            violationCount += 1
            updateViolations()
            val prompt = when (kind) {
                FrameDiffMotionDetector.TriggerKind.DRIFT -> voiceReturnToPosition
                FrameDiffMotionDetector.TriggerKind.INSTANT -> voiceStopMoving
                else -> null
            }
            if (prompt != null) {
                setHint(prompt)
                speak(prompt)
            }
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

    private fun stopSession(autoComplete: Boolean = false) {
        if (finishing) return
        finishing = true
        monitoring = false
        calibrating = false
        calibrationJob?.cancel()
        remainingJob?.cancel()
        remainingJob = null
        stopSpeaking()
        binding.cornertimeStop.isEnabled = false
        binding.cornertimeStart.isEnabled = true
        binding.cornertimeDuration.isEnabled = true
        binding.cornertimeRemaining.visibility = View.GONE
        CornertimeMonitoringService.stop(this)
        try {
            ProcessCameraProvider.getInstance(this).get().unbindAll()
        } catch (_: Exception) {
        }
        cameraExecutor?.shutdown()
        cameraExecutor = null
        poseDetector?.close()
        poseDetector = null
        sessionEndsAtMs = null

        val id = sessionId
        sessionId = null
        if (id != null) {
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) { repository.stopSession(id) }
                result.onSuccess { response ->
                    when {
                        response.early_stop == true ->
                            setStatus(getString(R.string.cornertime_status_early_stop))
                        autoComplete || response.session.status == "completed" ->
                            setStatus(getString(R.string.cornertime_status_completed))
                        else ->
                            setStatus(getString(R.string.cornertime_status_stopped))
                    }
                }.onFailure {
                    setStatus(getString(R.string.cornertime_status_error))
                    setHint(it.message)
                }
                finishing = false
            }
        } else {
            setStatus(
                if (autoComplete) getString(R.string.cornertime_status_completed)
                else getString(R.string.cornertime_status_stopped)
            )
            finishing = false
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
        tts?.shutdown()
        tts = null
        ttsReady = false
        super.onDestroy()
    }

    companion object {
        const val EXTRA_USE_POSE = "use_pose"
        private const val ANALYSIS_WIDTH = 160
        private const val ANALYSIS_HEIGHT = 120
        private const val PREFS_NAME = "cornertime"
        private const val PREF_VOICE_NAME = "tts_voice_name"
        private const val PREF_DURATION_MINUTES = "duration_minutes"
        private val DEFAULT_DURATIONS_MINUTES = listOf(1, 5, 10, 15, 20, 30, 45, 60)
        private val FEMALE_VOICE_RE = Pattern.compile(
            "female|woman|girl|samantha|victoria|karen|moira|fiona|tessa|amelie|amélie|hortense|denise|audrey|marie|virginie|zira|susan|linda|ava|emma|joanna|salli|ivy|kendra|kimberly|amy|aria|jenny|natalie|sofie|elsa|alva|nicky|heather|#female",
            Pattern.CASE_INSENSITIVE
        )
        private val MALE_VOICE_RE = Pattern.compile(
            "male|man|boy|david|daniel|alex|fred|thomas|paul|nicolas|jacques|mark|james|brian|matthew|joey|justin|kevin|guy|eric|#male",
            Pattern.CASE_INSENSITIVE
        )
    }
}
