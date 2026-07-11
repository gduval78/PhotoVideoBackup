import SwiftUI
import SwiftData
import UserNotifications

@main
struct PhotoVideoBackupApp: App {

    @State private var viewModel        = DashboardViewModel()
    @State private var storeManager     = StoreManager.shared
    @State private var browserViewModel = BackupBrowserViewModel()
    @State private var languageManager  = LanguageManager.shared
    private let notificationDelegate    = NotificationDisplayDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        _ = LanguageManager.shared
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        DiagnosticLog.pruneAndMarkLaunch(appVersion: version)
        // Lifecycle / memory / thermal / power / data-protection breadcrumbs.
        DiagnosticLog.installObservers()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Recreates the entire view tree when the language changes,
                // so all Text() calls pick up fresh localizedString results.
                .id(languageManager.selectedCode)
                // Sets SwiftUI's locale so Text(LocalizedStringKey) uses the right .lproj.
                // LanguageBundle (Bundle.main subclass) handles String(localized:) in ViewModels.
                .environment(\.locale, languageManager.currentLocale)
                .environment(viewModel)
                .environment(storeManager)
                .environment(browserViewModel)
                .environment(languageManager)
                .onAppear { viewModel.requestNotificationPermission() }
        }
        .modelContainer(IndexStore.shared.container)
    }
}

// Shows notifications as banners even when the app is in the foreground.
private final class NotificationDisplayDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
