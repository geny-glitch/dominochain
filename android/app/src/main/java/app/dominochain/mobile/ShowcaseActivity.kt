package app.dominochain.mobile

import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityShowcaseBinding
import kotlinx.coroutines.launch

class ShowcaseActivity : BetaShellActivity() {

    private lateinit var binding: ActivityShowcaseBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val authRepository = AuthRepository()

    private var showcaseListenerQuiet = false
    private var lastLoadedQuizSecondsPerPoint = 1
    private var lastLoadedSnakeSecondsPerFruit = 300
    private var lastLoadedDinoSecondsPerObstacle = 300
    private var lastLoadedTetrisSecondsPerLine = 60

    override val navDestination = AppNavDestination.SOURCE_SHOWCASE

    override fun onCreateContent(container: FrameLayout) {
        binding = ActivityShowcaseBinding.inflate(layoutInflater, container, true)
        RetrofitClient.sessionManager = sessionManager
        setupShowcaseControls()
        setupLinks()
        loadShowcaseSettings()
    }

    override fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) {
        if (!isBeta || !config.sourceEnabled("showcase")) {
            openDestination(AppNavDestination.HOME)
        }
    }

    private fun setupLinks() {
        val nick = sessionManager.nickname?.trim().orEmpty()
        if (nick.isEmpty()) return
        val base = BuildConfig.API_BASE_URL.trimEnd('/')
        val vitrineUrl = "$base/showcase/$nick"
        val backdoorUrl = "$base/showcase/$nick/backdoor"
        binding.showcaseOpenVitrine.setOnClickListener { openUrl(vitrineUrl) }
        binding.showcaseOpenBackdoor.setOnClickListener { openUrl(backdoorUrl) }
    }

    private fun controls() = binding.showcaseControls

    private fun setupShowcaseControls() {
        val c = controls()
        val switches = listOf(
            c.showcaseQuizSwitch,
            c.showcaseSnakeSwitch,
            c.showcaseDinoSwitch,
            c.showcaseTetrisSwitch,
            c.showcaseBackdoorSwitch
        )
        switches.forEach { switch ->
            switch.setOnCheckedChangeListener { view, checked ->
                if (showcaseListenerQuiet) return@setOnCheckedChangeListener
                val anyOtherOn = switches.any { it !== view && it.isChecked }
                if (!checked && !anyOtherOn) {
                    showcaseListenerQuiet = true
                    view.isChecked = true
                    showcaseListenerQuiet = false
                    Toast.makeText(this, R.string.showcase_least_one_game, Toast.LENGTH_SHORT).show()
                    return@setOnCheckedChangeListener
                }
                saveShowcaseSettings()
            }
        }
        c.showcaseQuizSecondsSave.setOnClickListener { saveShowcaseSecondsInputs() }
        c.showcaseSnakeSecondsSave.setOnClickListener { saveShowcaseSecondsInputs() }
        c.showcaseDinoSecondsSave.setOnClickListener { saveShowcaseSecondsInputs() }
        c.showcaseTetrisSecondsSave.setOnClickListener { saveShowcaseSecondsInputs() }
    }

    private fun loadShowcaseSettings() {
        lifecycleScope.launch {
            authRepository.getShowcaseSettings()
                .onSuccess { st ->
                    val c = controls()
                    showcaseListenerQuiet = true
                    c.showcaseQuizSwitch.isChecked = st.showcase_quiz_enabled
                    c.showcaseSnakeSwitch.isChecked = st.showcase_snake_enabled
                    c.showcaseDinoSwitch.isChecked = st.showcase_dino_enabled ?: true
                    c.showcaseTetrisSwitch.isChecked = st.showcase_tetris_enabled ?: true
                    c.showcaseBackdoorSwitch.isChecked = st.showcase_backdoor_enabled
                    val quizSec = st.showcase_quiz_seconds_per_point?.takeIf { it > 0 } ?: 1
                    val snakeSec = st.showcase_snake_seconds_per_fruit?.takeIf { it > 0 } ?: 300
                    val dinoSec = st.showcase_dino_seconds_per_obstacle?.takeIf { it > 0 } ?: 300
                    val tetrisSec = st.showcase_tetris_seconds_per_line?.takeIf { it > 0 } ?: 60
                    lastLoadedQuizSecondsPerPoint = quizSec
                    lastLoadedSnakeSecondsPerFruit = snakeSec
                    lastLoadedDinoSecondsPerObstacle = dinoSec
                    lastLoadedTetrisSecondsPerLine = tetrisSec
                    c.showcaseQuizSecondsInput.setText(quizSec.toString())
                    c.showcaseSnakeSecondsInput.setText(snakeSec.toString())
                    c.showcaseDinoSecondsInput.setText(dinoSec.toString())
                    c.showcaseTetrisSecondsInput.setText(tetrisSec.toString())
                    binding.showcaseOpenBackdoor.visibility =
                        if (st.showcase_backdoor_enabled) View.VISIBLE else View.GONE
                    showcaseListenerQuiet = false
                }
        }
    }

    private fun saveShowcaseSecondsInputs() {
        val c = controls()
        val quizSeconds = c.showcaseQuizSecondsInput.text.toString().trim().toIntOrNull()
        val snakeSeconds = c.showcaseSnakeSecondsInput.text.toString().trim().toIntOrNull()
        val dinoSeconds = c.showcaseDinoSecondsInput.text.toString().trim().toIntOrNull()
        val tetrisSeconds = c.showcaseTetrisSecondsInput.text.toString().trim().toIntOrNull()
        if (quizSeconds == null || quizSeconds <= 0 || snakeSeconds == null || snakeSeconds <= 0 ||
            dinoSeconds == null || dinoSeconds <= 0 || tetrisSeconds == null || tetrisSeconds <= 0
        ) {
            Toast.makeText(this, R.string.showcase_seconds_invalid, Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            authRepository.updateShowcaseSettings(
                c.showcaseQuizSwitch.isChecked,
                c.showcaseSnakeSwitch.isChecked,
                c.showcaseDinoSwitch.isChecked,
                c.showcaseTetrisSwitch.isChecked,
                c.showcaseBackdoorSwitch.isChecked,
                quizSeconds,
                snakeSeconds,
                dinoSeconds,
                tetrisSeconds
            ).onSuccess {
                Toast.makeText(this@ShowcaseActivity, R.string.showcase_seconds_saved, Toast.LENGTH_SHORT).show()
                loadShowcaseSettings()
            }.onFailure { err ->
                Toast.makeText(
                    this@ShowcaseActivity,
                    err.message ?: getString(R.string.showcase_settings_error),
                    Toast.LENGTH_SHORT
                ).show()
                loadShowcaseSettings()
            }
        }
    }

    private fun saveShowcaseSettings() {
        val c = controls()
        val quizSec = c.showcaseQuizSecondsInput.text.toString().trim()
            .toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedQuizSecondsPerPoint
        val snakeSec = c.showcaseSnakeSecondsInput.text.toString().trim()
            .toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedSnakeSecondsPerFruit
        val dinoSec = c.showcaseDinoSecondsInput.text.toString().trim()
            .toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedDinoSecondsPerObstacle
        val tetrisSec = c.showcaseTetrisSecondsInput.text.toString().trim()
            .toIntOrNull()?.takeIf { it > 0 } ?: lastLoadedTetrisSecondsPerLine
        lifecycleScope.launch {
            authRepository.updateShowcaseSettings(
                c.showcaseQuizSwitch.isChecked,
                c.showcaseSnakeSwitch.isChecked,
                c.showcaseDinoSwitch.isChecked,
                c.showcaseTetrisSwitch.isChecked,
                c.showcaseBackdoorSwitch.isChecked,
                quizSec,
                snakeSec,
                dinoSec,
                tetrisSec
            ).onSuccess {
                binding.showcaseOpenBackdoor.visibility =
                    if (c.showcaseBackdoorSwitch.isChecked) View.VISIBLE else View.GONE
            }.onFailure { err ->
                Toast.makeText(
                    this@ShowcaseActivity,
                    err.message ?: getString(R.string.showcase_settings_error),
                    Toast.LENGTH_SHORT
                ).show()
                loadShowcaseSettings()
            }
        }
    }

    private fun openUrl(url: String) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: Exception) {
            Toast.makeText(this, R.string.open_url_failed, Toast.LENGTH_SHORT).show()
        }
    }
}
