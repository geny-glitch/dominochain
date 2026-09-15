package app.dominochain.mobile

import app.dominochain.mobile.api.ShowcaseSettingsResponse

/**
 * Resolved feature-flag + user-settings visibility for Android UI sections.
 * Missing keys default to true (fail-open) so network errors, non-beta 403s,
 * or an older backend never hide sections unexpectedly.
 */
data class AppSectionsConfig(
    private val sources: Map<String, Boolean> = emptyMap(),
    private val actions: Map<String, Boolean> = emptyMap(),
    private val capabilities: Map<String, Boolean> = emptyMap()
) {
    fun sourceEnabled(id: String) = sources[id] ?: true

    fun actionEnabled(id: String) = actions[id] ?: true

    fun sectionVisible(id: String) = capabilities[id] ?: true

    companion object {
        val DEFAULT = AppSectionsConfig()

        fun from(response: ShowcaseSettingsResponse?): AppSectionsConfig = AppSectionsConfig(
            sources = response?.catalog?.sources ?: emptyMap(),
            actions = response?.catalog?.actions ?: emptyMap(),
            capabilities = response?.capabilities ?: emptyMap()
        )
    }
}
