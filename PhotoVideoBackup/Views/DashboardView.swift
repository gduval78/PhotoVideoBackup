import SwiftUI
import UIKit
import StoreKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @Environment(LanguageManager.self)    private var languageManager
    @Environment(\.requestReview)         private var requestReview
    @State private var showSourcePicker      = false
    @State private var showPaywall           = false
    @State private var pendingSourceURL:     URL?
    @State private var pendingSourceData:    Data?
    @State private var pendingSourceName:    String = ""
    @State private var reconnectingSourceID: UUID?
    @AppStorage("deviceName") private var deviceName: String = ""

    var body: some View {
        List {
            destinationsSection
            sourcesSection

            if viewModel.isRunning {
                Section {
                    SessionProgressView()
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }
            } else if let banner = viewModel.completionBanner {
                completionBannerSection(banner)
            }
        }
        .navigationTitle("PhotoVideoBackup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.refreshDestinationStatuses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isRunning)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.refreshDestinationStatuses()
        }
        .onChange(of: viewModel.shouldRequestReview) { _, requested in
            guard requested else { return }
            requestReview()
            viewModel.clearReviewRequest()
        }
        .alert("Backup Error", isPresented: .constant(viewModel.backupError != nil)) {
            Button("OK") { viewModel.backupError = nil }
        } message: {
            Text(viewModel.backupError ?? "")
        }
        .fileImporter(
            isPresented: $showSourcePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            // Create bookmark immediately while the security scope is still active.
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            url.stopAccessingSecurityScopedResource()
            if let reconnectID = reconnectingSourceID, let bm = bookmark {
                viewModel.reconnectSource(id: reconnectID, url: url, bookmarkData: bm)
                reconnectingSourceID = nil
            } else {
                pendingSourceURL  = url
                pendingSourceData = bookmark
                pendingSourceName = url.lastPathComponent
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Name this source", isPresented: Binding(
            get: { pendingSourceData != nil },
            set: { if !$0 { pendingSourceURL = nil; pendingSourceData = nil; pendingSourceName = "" } }
        )) {
            TextField("e.g. Blackmagic, GoPro…", text: $pendingSourceName)
            Button("Add") {
                if let url = pendingSourceURL, let bookmark = pendingSourceData {
                    viewModel.addExternalSource(
                        url: url,
                        bookmarkData: bookmark,
                        customName: pendingSourceName.trimmingCharacters(in: .whitespaces)
                    )
                }
                pendingSourceURL  = nil
                pendingSourceData = nil
                pendingSourceName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingSourceURL  = nil
                pendingSourceData = nil
                pendingSourceName = ""
            }
        } message: {
            Text("Give this source a name so you can recognise it easily.")
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        Section("Destinations") {
            if viewModel.destinationStatuses.isEmpty {
                Label("No destination configured — go to Settings.",
                      systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.destinationStatuses) { status in
                    DestinationRow(status: status)
                }
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        Section("Sources") {
            // Device name warning
            if deviceName.isEmpty {
                Label("Set a device name in Settings.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Photos Library — always visible
            SourceRow(
                icon: "photo.on.rectangle.angled",
                iconColor: .blue,
                nameContent: { Text("Photos Library") },
                subtitleContent: {
                    if deviceName.isEmpty {
                        Text("Name not configured")
                    } else {
                        Text(verbatim: deviceName) + Text(verbatim: " · ") + Text("all photos & videos")
                    }
                },
                isRunning: viewModel.isRunning,
                destinationsEmpty: !viewModel.hasConnectedDestination
            ) {
                Task { await viewModel.startBackup() }
            }

            // User-added external sources (SD cards, USB drives)
            ForEach(viewModel.externalSources) { source in
                SourceRow(
                    icon: iconName(for: source.deviceType),
                    iconColor: source.isAvailable ? iconColor(for: source.deviceType) : .secondary,
                    nameContent: { Text(verbatim: source.displayName) },
                    subtitleContent: {
                        if source.isAvailable {
                            Text(verbatim: source.deviceType.rawValue)
                        } else {
                            Text("Not connected")
                        }
                    },
                    isRunning: viewModel.isRunning,
                    destinationsEmpty: !viewModel.hasConnectedDestination || !source.isAvailable,
                    onReconnect: source.isAvailable ? nil : {
                        if ProcessInfo.processInfo.isiOSAppOnMac {
                            guard let url = MacOpenPanel.pickFolder() else { return }
                            _ = url.startAccessingSecurityScopedResource()
                            let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                            url.stopAccessingSecurityScopedResource()
                            guard let bm else { return }
                            viewModel.reconnectSource(id: source.id, url: url, bookmarkData: bm)
                        } else {
                            reconnectingSourceID = source.id
                            showSourcePicker = true
                        }
                    },
                    onRemove: { viewModel.removeExternalSource(id: source.id) }
                ) {
                    Task { await viewModel.startBackup(from: source) }
                }
            }

            // Add Source button — Pro only
            Button {
                if store.isPremium {
                    if ProcessInfo.processInfo.isiOSAppOnMac {
                        guard let url = MacOpenPanel.pickFolder() else { return }
                        _ = url.startAccessingSecurityScopedResource()
                        let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                        url.stopAccessingSecurityScopedResource()
                        pendingSourceURL  = url
                        pendingSourceData = bm
                        pendingSourceName = url.lastPathComponent
                    } else {
                        showSourcePicker = true
                    }
                } else {
                    showPaywall = true
                }
            } label: {
                Label {
                    HStack {
                        Text("Add Source (SD Card, USB Drive…)")
                        Spacer()
                        if !store.isPremium {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: "plus.circle")
                }
            }
            .disabled(viewModel.isRunning)
        }
    }

    // MARK: - Completion Banner

    @ViewBuilder
    private func completionBannerSection(_ banner: DashboardViewModel.CompletionBanner) -> some View {
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

    // MARK: - Helpers

    private func statLabel(_ text: LocalizedStringKey, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).foregroundStyle(color)
    }

    private func iconName(for type: DeviceType) -> String {
        switch type {
        case .insta360X5:  return "camera.aperture"
        case .djiMini3Pro: return "airplane"
        case .dji360:      return "video.badge.waveform"
        case .gopro:       return "camera.fill"
        case .generic:     return "sdcard"
        }
    }

    private func iconColor(for type: DeviceType) -> Color {
        switch type {
        case .insta360X5:  return .purple
        case .djiMini3Pro: return .blue
        case .dji360:      return .teal
        case .gopro:       return .red
        case .generic:     return .orange
        }
    }
}

// MARK: - DestinationRow

private struct DestinationRow: View {
    let status: DestinationStatus
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(status.displayName, systemImage: "externaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(status.isConnected ? .primary : .secondary)
                Spacer()
                if status.isConnected {
                    Text("\(status.formattedAvailable(locale: languageManager.currentLocale)) free")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Disconnected")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            if !status.folderPath.isEmpty {
                Text(status.folderPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if status.isConnected {
                ProgressView(value: status.usedFraction)
                    .tint(status.usedFraction > 0.9 ? .red : .accentColor)
                Text("\(status.formattedTotal(locale: languageManager.currentLocale)) total")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - SourceRow

private struct SourceRow<Name: View, Subtitle: View>: View {
    let icon: String
    let iconColor: Color
    @ViewBuilder let nameContent: () -> Name
    @ViewBuilder let subtitleContent: () -> Subtitle
    let isRunning: Bool
    let destinationsEmpty: Bool
    var onReconnect: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    let onBackup: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                nameContent().font(.subheadline.weight(.medium))
                subtitleContent().font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let onRemove {
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .disabled(isRunning)
            }

            if let onReconnect {
                Button("Reconnect") { onReconnect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning)
            } else {
                Button("Backup") { onBackup() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning || destinationsEmpty)
            }
        }
        .padding(.vertical, 2)
    }
}
