import SwiftUI

struct ContentView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(BackupBrowserViewModel.self) private var browser
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Backup", systemImage: "arrow.triangle.2.circlepath.circle.fill")
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
        .onAppear { viewModel.onAppear() }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }
}
