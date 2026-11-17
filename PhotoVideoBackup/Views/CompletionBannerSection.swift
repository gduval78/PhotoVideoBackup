import SwiftUI

/// The "backup finished" card, shared by the Advanced dashboard and the Backups (profiles) screen.
struct CompletionBannerSection: View {
    let banner: DashboardViewModel.CompletionBanner
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    switch banner.status {
                    case .completed:
                        Label("Backup Complete", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                    case .partial:
                        Label("Partial Backup", systemImage: "exclamationmark.arrow.circlepath")
                            .font(.headline).foregroundStyle(.orange)
                    case .failed:
                        Label("Backup Failed", systemImage: "xmark.circle.fill")
                            .font(.headline).foregroundStyle(.red)
                    case .running:
                        EmptyView()
                    }
                    Spacer()
                    Button {
                        viewModel.dismissCompletionBanner()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text(banner.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 20) {
                    statLabel("\(banner.copiedCount) copied",  icon: "doc.fill",    color: .green)
                    statLabel("\(banner.skippedCount) skipped", icon: "minus.circle", color: .orange)
                    statLabel("\(banner.failedCount) failed",
                              icon: "xmark.circle",
                              color: banner.failedCount > 0 ? Color.red : Color.secondary)
                }
                .font(.subheadline)

                if banner.verifiedCount > 0 {
                    Label("\(banner.verifiedCount) verified by SHA-256", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }

                Text(banner.totalBytesCopied.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))
                     + " — " + String(format: "%.1f s", banner.durationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    
    }

    private func statLabel(_ text: LocalizedStringKey, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).foregroundStyle(color)
    }
}
