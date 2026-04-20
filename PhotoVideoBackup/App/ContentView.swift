import SwiftUI

struct ContentView: View {
    @Environment(DashboardViewModel.self) private var viewModel

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
    }
}
