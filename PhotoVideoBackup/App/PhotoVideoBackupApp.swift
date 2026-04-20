import SwiftUI
import SwiftData
import UserNotifications

@main
struct PhotoVideoBackupApp: App {

    @State private var viewModel       = DashboardViewModel()
    @State private var storeManager    = StoreManager.shared
    @State private var browserViewModel = BackupBrowserViewModel()
    private let notificationDelegate   = NotificationDisplayDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(storeManager)
                .environment(browserViewModel)
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
