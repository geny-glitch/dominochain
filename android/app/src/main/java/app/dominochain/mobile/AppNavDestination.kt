package app.dominochain.mobile

import android.content.Context
import android.content.Intent

/**
 * Drawer destinations mirroring the web beta sidebar groups:
 * View → Sources → Actions → Personal.
 */
enum class AppNavDestination {
    HOME,
    SOURCE_CIGARETTES,
    SOURCE_SHOWCASE,
    SOURCE_WALLPAPER,
    SOURCE_CORNERTIME,
    ACTION_CHASTER,
    ACTION_LEVERAGE_PHOTO,
    ACCOUNT,
    TASKS;

    fun createIntent(context: Context): Intent = when (this) {
        HOME -> Intent(context, MainActivity::class.java)
        SOURCE_CIGARETTES -> Intent(context, CigaretteHistoryActivity::class.java)
        SOURCE_SHOWCASE -> Intent(context, ShowcaseActivity::class.java)
        SOURCE_WALLPAPER -> Intent(context, WallpaperActivity::class.java)
        SOURCE_CORNERTIME -> Intent(context, CornertimeActivity::class.java)
        ACTION_CHASTER -> Intent(context, ChasterHistoryActivity::class.java)
        ACTION_LEVERAGE_PHOTO -> Intent(context, LeveragePhotosActivity::class.java)
        ACCOUNT -> Intent(context, SettingsActivity::class.java)
        TASKS -> Intent(context, TasksActivity::class.java)
    }

    fun titleRes(): Int = when (this) {
        HOME -> R.string.nav_home
        SOURCE_CIGARETTES -> R.string.nav_source_cigarettes
        SOURCE_SHOWCASE -> R.string.nav_source_showcase
        SOURCE_WALLPAPER -> R.string.nav_source_wallpaper
        SOURCE_CORNERTIME -> R.string.nav_source_cornertime
        ACTION_CHASTER -> R.string.nav_action_chaster
        ACTION_LEVERAGE_PHOTO -> R.string.nav_action_leverage_photo
        ACCOUNT -> R.string.nav_account
        TASKS -> R.string.nav_tasks
    }

    fun isVisible(config: AppSectionsConfig, isBeta: Boolean): Boolean = when (this) {
        HOME -> true
        SOURCE_CIGARETTES -> config.sourceEnabled("cigarettes")
        SOURCE_SHOWCASE -> isBeta && config.sourceEnabled("showcase")
        SOURCE_WALLPAPER -> config.sourceEnabled("wallpaper")
        SOURCE_CORNERTIME -> config.sourceEnabled("cornertime")
        ACTION_CHASTER -> config.actionEnabled("chaster") && config.sectionVisible("chaster")
        ACTION_LEVERAGE_PHOTO -> config.actionEnabled("leverage_photo")
        ACCOUNT -> true
        TASKS -> config.sectionVisible("tasks")
    }

    companion object {
        val VIEW_ITEMS = listOf(HOME)
        val SOURCE_ITEMS = listOf(
            SOURCE_CIGARETTES,
            SOURCE_SHOWCASE,
            SOURCE_WALLPAPER,
            SOURCE_CORNERTIME
        )
        val ACTION_ITEMS = listOf(
            ACTION_CHASTER,
            ACTION_LEVERAGE_PHOTO
        )
        val PERSONAL_ITEMS = listOf(ACCOUNT, TASKS)
    }
}
