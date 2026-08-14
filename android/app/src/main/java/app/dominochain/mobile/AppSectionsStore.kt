package app.dominochain.mobile

/**
 * Shared in-memory visibility state for the beta drawer / pages.
 * Updated whenever a shell activity refreshes showcase_settings.
 */
object AppSectionsStore {
    @Volatile
    var config: AppSectionsConfig = AppSectionsConfig.DEFAULT

    @Volatile
    var userIsBeta: Boolean = false
}
