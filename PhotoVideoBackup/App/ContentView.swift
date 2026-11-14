import SwiftUI

struct ContentView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(BackupBrowserViewModel.self) private var browser
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// The pre-profiles dashboard. Shown to users who upgraded with a setup, and on request
    /// (Settings → Interface) for everyone else.
    @AppStorage("showAdvancedScreens") private var showAdvanced = false

    var body: some View {
        TabView {
            NavigationStack {
                BackupsView()
            }
            .tabItem {
                Label("Backups", systemImage: "arrow.triangle.2.circlepath.circle.fill")
            }

            if showAdvanced {
                NavigationStack {
                    DashboardView()
                }
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }

            NavigationStack {
                BackupBrowserView()
            }
            .onAppear  { browser.startAccess() }
            .onDisappear { browser.stopAccess() }
            .tabItem {
                Label("Browse", systemImage: "photo.stack.fill")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .modifier(BackupAlerts())
        .onAppear {
            DiagnosticLog.markUIReady()
            viewModel.onAppear()
            migrateProfilesIfNeeded()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }

    /// First launch of 2.7.0: turn what an upgrade already had configured into profiles, so nothing
    /// has to be set up again. Runs after `onAppear` has loaded the persisted sources.
    private func migrateProfilesIfNeeded() {
        let dm = DestinationManager.shared
        let keys = (0...1).map { dm.key(for: $0) }.filter { dm.isConfigured(forKey: $0) }
        let sources = viewModel.externalSources.map { ProfileMigration.LegacySource(id: $0.id, name: $0.displayName) }
        ProfileStore.shared.migrateIfNeeded(
            configuredFolderKeys: keys, nasConfigured: dm.isNASConfigured(), externalSources: sources,
            photosName: String(localized: "Photos Library"), nasName: String(localized: "NAS"))
    }
}
