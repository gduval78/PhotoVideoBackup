package gduvalsc.photovideobackup.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import gduvalsc.photovideobackup.Prefs
import gduvalsc.photovideobackup.R

private enum class Tab { BACKUP, BROWSE, HISTORY, SETTINGS }

/** Full-screen pages pushed over the tabs. */
private sealed interface Page {
    data object Paywall : Page
    data object Naming : Page
    data object Extensions : Page
    data object Nas : Page
    data object Diagnostic : Page
    data object Welcome : Page
    data class Report(val sessionId: String) : Page
}

@Composable
fun AppRoot() {
    var tab by rememberSaveable { mutableStateOf(Tab.BACKUP) }
    var page by androidx.compose.runtime.remember { mutableStateOf<Page?>(if (Prefs.onboardingDone) null else Page.Welcome) }

    BackHandler(enabled = page != null && page != Page.Welcome) { page = null }

    Surface(Modifier.fillMaxSize()) {
        val p = page
        if (p != null) {
            Box(Modifier.fillMaxSize().statusBarsPadding()) {
                when (p) {
                    Page.Welcome -> OnboardingScreen { Prefs.onboardingDone = true; page = null }
                    Page.Paywall -> PaywallScreen { page = null }
                    Page.Naming -> NamingScreen { page = null }
                    Page.Extensions -> ExtensionsScreen { page = null }
                    Page.Nas -> NasScreen { page = null }
                    Page.Diagnostic -> DiagnosticScreen { page = null }
                    is Page.Report -> ReportScreen(p.sessionId) { page = null }
                }
            }
        } else {
            Scaffold(
                bottomBar = {
                    NavigationBar {
                        NavigationBarItem(tab == Tab.BACKUP, { tab = Tab.BACKUP }, { Icon(Icons.Default.Storage, null) }, label = { Text(stringResource(R.string.backup)) })
                        NavigationBarItem(tab == Tab.BROWSE, { tab = Tab.BROWSE }, { Icon(Icons.Default.FolderOpen, null) }, label = { Text(stringResource(R.string.tab_browse)) })
                        NavigationBarItem(tab == Tab.HISTORY, { tab = Tab.HISTORY }, { Icon(Icons.Default.History, null) }, label = { Text(stringResource(R.string.history)) })
                        NavigationBarItem(tab == Tab.SETTINGS, { tab = Tab.SETTINGS }, { Icon(Icons.Default.Settings, null) }, label = { Text(stringResource(R.string.settings)) })
                    }
                },
            ) { inner: PaddingValues ->
                Box(Modifier.padding(inner).statusBarsPadding()) {
                    when (tab) {
                        Tab.BACKUP -> DashboardScreen(onGoSettings = { tab = Tab.SETTINGS }, onPaywall = { page = Page.Paywall })
                        Tab.BROWSE -> BrowseScreen()
                        Tab.HISTORY -> HistoryScreen(onOpen = { page = Page.Report(it) })
                        Tab.SETTINGS -> SettingsScreen(
                            onPaywall = { page = Page.Paywall }, onNaming = { page = Page.Naming },
                            onExtensions = { page = Page.Extensions }, onNas = { page = Page.Nas },
                            onDiagnostic = { page = Page.Diagnostic }, onWelcome = { page = Page.Welcome },
                        )
                    }
                }
            }
        }
    }
}
