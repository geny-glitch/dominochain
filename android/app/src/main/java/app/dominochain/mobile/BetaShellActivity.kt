package app.dominochain.mobile

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.ActionBarDrawerToggle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.GravityCompat
import androidx.lifecycle.lifecycleScope
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityBetaShellBinding
import kotlinx.coroutines.launch

/**
 * Shared shell with a sidebar drawer matching the web beta dashboard groups
 * (View / Sources / Actions / Personal).
 */
abstract class BetaShellActivity : AppCompatActivity() {

    protected lateinit var shell: ActivityBetaShellBinding
    private lateinit var drawerToggle: ActionBarDrawerToggle
    private val authRepository = AuthRepository()

    protected abstract val navDestination: AppNavDestination

    /** Inflate page content into [container] (attach to parent). */
    protected abstract fun onCreateContent(container: FrameLayout)

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(R.style.Theme_Bg_NoActionBar)
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = (application as BgApplication).sessionManager

        shell = ActivityBetaShellBinding.inflate(layoutInflater)
        setContentView(shell.root)
        setSupportActionBar(shell.toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(navDestination.titleRes())

        onCreateContent(shell.contentContainer)
        setupDrawer()
        refreshSectionsConfig()
    }

    override fun onResume() {
        super.onResume()
        refreshSectionsConfig()
    }

    override fun onPostCreate(savedInstanceState: Bundle?) {
        super.onPostCreate(savedInstanceState)
        drawerToggle.syncState()
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (drawerToggle.onOptionsItemSelected(item)) return true
        return super.onOptionsItemSelected(item)
    }

    override fun onBackPressed() {
        if (shell.drawerLayout.isDrawerOpen(GravityCompat.START)) {
            shell.drawerLayout.closeDrawer(GravityCompat.START)
            return
        }
        if (navDestination != AppNavDestination.HOME) {
            openDestination(AppNavDestination.HOME)
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    protected fun openDestination(destination: AppNavDestination) {
        if (destination == navDestination) {
            shell.drawerLayout.closeDrawer(GravityCompat.START)
            return
        }
        val intent = destination.createIntent(this)
        when {
            destination == AppNavDestination.HOME -> {
                intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                startActivity(intent)
            }
            navDestination == AppNavDestination.HOME -> startActivity(intent)
            else -> {
                startActivity(intent)
                finish()
            }
        }
        shell.drawerLayout.closeDrawer(GravityCompat.START)
    }

    private fun setupDrawer() {
        drawerToggle = ActionBarDrawerToggle(
            this,
            shell.drawerLayout,
            shell.toolbar,
            R.string.nav_open_menu,
            R.string.nav_close_menu
        )
        shell.drawerLayout.addDrawerListener(drawerToggle)
        drawerToggle.syncState()

        val nickname = (application as BgApplication).sessionManager.nickname.orEmpty()
        shell.navigationView.getHeaderView(0)
            ?.findViewById<TextView>(R.id.nav_header_nickname)
            ?.text = nickname.ifBlank { getString(R.string.empty_placeholder) }

        rebuildDrawerMenu()
        shell.navigationView.setNavigationItemSelectedListener { item ->
            val dest = AppNavDestination.entries.find { it.ordinal == item.itemId }
            if (dest != null) openDestination(dest)
            true
        }
    }

    private fun rebuildDrawerMenu() {
        val menu = shell.navigationView.menu
        menu.clear()
        val config = AppSectionsStore.config
        val isBeta = AppSectionsStore.userIsBeta

        addGroup(menu, R.string.nav_group_view, AppNavDestination.VIEW_ITEMS, config, isBeta)
        addGroup(menu, R.string.nav_group_sources, AppNavDestination.SOURCE_ITEMS, config, isBeta)
        addGroup(menu, R.string.nav_group_actions, AppNavDestination.ACTION_ITEMS, config, isBeta)
        addGroup(menu, R.string.nav_group_personal, AppNavDestination.PERSONAL_ITEMS, config, isBeta)

        shell.navigationView.setCheckedItem(navDestination.ordinal)
    }

    private fun addGroup(
        menu: Menu,
        titleRes: Int,
        items: List<AppNavDestination>,
        config: AppSectionsConfig,
        isBeta: Boolean
    ) {
        val visible = items.filter { it.isVisible(config, isBeta) }
        if (visible.isEmpty()) return
        val groupId = titleRes
        val submenu = menu.addSubMenu(groupId, Menu.NONE, Menu.NONE, titleRes)
        visible.forEach { dest ->
            submenu.add(groupId, dest.ordinal, Menu.NONE, dest.titleRes())
                .setCheckable(true)
                .isChecked = dest == navDestination
        }
    }

    private fun refreshSectionsConfig() {
        lifecycleScope.launch {
            val me = authRepository.getMe().getOrNull()
            val settings = authRepository.getShowcaseSettings().getOrNull()
            AppSectionsStore.config = AppSectionsConfig.from(settings)
            AppSectionsStore.userIsBeta = me != null && (me.role == null || me.role == "beta")
            rebuildDrawerMenu()
            onSectionsConfigUpdated(AppSectionsStore.config, AppSectionsStore.userIsBeta)
        }
    }

    /** Optional hook when catalog/capabilities refresh completes. */
    protected open fun onSectionsConfigUpdated(config: AppSectionsConfig, isBeta: Boolean) = Unit

    protected fun contentContainer(): FrameLayout = shell.contentContainer
}
