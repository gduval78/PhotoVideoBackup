import SwiftUI

/// The alerts every way of starting a backup can raise — the backup error and the iCloud Drive
/// warning. Attached once, at the TabView level, so a screen that is not on top never presents them.
struct BackupAlerts: ViewModifier {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager

    func body(content: Content) -> some View {
        content
            .alert("iCloud Drive can be slow", isPresented: Binding(
                get: { viewModel.iCloudWarningFreeBytes != nil },
                set: { if !$0 { viewModel.cancelICloudWarning() } }
            )) {
                Button("Back up anyway") { viewModel.confirmICloudWarning() }
                Button("Cancel", role: .cancel) { viewModel.cancelICloudWarning() }
            } message: {
                let free = (viewModel.iCloudWarningFreeBytes ?? 0)
                    .formatted(.byteCount(style: .file).locale(languageManager.currentLocale))
                Text("Files are first written on this iPhone, then iOS uploads them to iCloud when it decides to. Your iPhone has only \(free) free, so a large library can take many hours, and the backup may stop if the iPhone or your iCloud storage is full. An external drive or a NAS is safer and much faster.")
            }
            .alert("Backup Error", isPresented: .constant(viewModel.backupError != nil)) {
                Button("OK") { viewModel.backupError = nil }
            } message: {
                Text(viewModel.backupError ?? "")
            }
    }
}
