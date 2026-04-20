import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @State private var showSourcePicker = false
    @State private var showPaywall      = false
    @State private var pendingSourceURL: URL?
    @State private var pendingSourceName: String = ""
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
        .alert("Backup Error", isPresented: .constant(viewModel.backupError != nil)) {
            Button("OK") { viewModel.backupError = nil }
        } message: {
            Text(viewModel.backupError ?? "")
        }
        .sheet(isPresented: $showSourcePicker) {
            FolderPickerView(initialDirectory: nil) { url in
                showSourcePicker = false
                pendingSourceURL = url
                pendingSourceName = url.lastPathComponent
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert("Name this source", isPresented: Binding(
            get: { pendingSourceURL != nil },
            set: { if !$0 { pendingSourceURL = nil; pendingSourceName = "" } }
        )) {
            TextField("e.g. Blackmagic, GoPro…", text: $pendingSourceName)
            Button("Add") {
                if let url = pendingSourceURL {
                    viewModel.addExternalSource(
                        url: url,
                        customName: pendingSourceName.trimmingCharacters(in: .whitespaces)
                    )
                }
                pendingSourceURL  = nil
                pendingSourceName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingSourceURL  = nil
                pendingSourceName = ""
            }
        } message: {
            Text("Give this source a name so you can recognise it easily.")
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        Section("SSD Destinations") {
            if viewModel.destinationStatuses.isEmpty {
                Label("No SSD configured — go to Settings.",
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
                name: "Photos Library",
                subtitle: deviceName.isEmpty ? "Name not configured" : "\(deviceName) · all photos & videos",
                isRunning: viewModel.isRunning,
                destinationsEmpty: viewModel.destinationStatuses.isEmpty
            ) {
                Task { await viewModel.startBackup() }
            }

            // User-added external sources (SD cards, USB drives)
            ForEach(viewModel.externalSources) { source in
                SourceRow(
                    icon: iconName(for: source.deviceType),
                    iconColor: iconColor(for: source.deviceType),
                    name: source.displayName,
                    subtitle: source.deviceType.rawValue,
                    isRunning: viewModel.isRunning,
                    destinationsEmpty: viewModel.destinationStatuses.isEmpty,
                    onRemove: { viewModel.removeExternalSource(id: source.id) }
                ) {
                    Task { await viewModel.startBackup(from: source) }
                }
            }

            // Add Source button — Pro only
            Button {
                if store.isPremium {
                    showSourcePicker = true
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

                Text(ByteCountFormatter.string(fromByteCount: banner.totalBytesCopied, countStyle: .file)
                     + " — " + String(format: "%.1f s", banner.durationSeconds))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func statLabel(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon).foregroundStyle(color)
    }

    private func iconName(for type: DeviceType) -> String {
        switch type {
        case .insta360X5:  return "camera.aperture"
        case .djiMini3Pro: return "airplane"
        case .dji360:      return "video.badge.waveform"
        case .generic:     return "sdcard"
        }
    }

    private func iconColor(for type: DeviceType) -> Color {
        switch type {
        case .insta360X5:  return .purple
        case .djiMini3Pro: return .blue
        case .dji360:      return .teal
        case .generic:     return .orange
        }
    }
}

// MARK: - DestinationRow

private struct DestinationRow: View {
    let status: DestinationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(status.displayName, systemImage: "externaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(status.isConnected ? .primary : .secondary)
                Spacer()
                if status.isConnected {
                    Text(status.formattedAvailable + " free")
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
                Text(status.formattedTotal + " total")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - SourceRow

private struct SourceRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let subtitle: String
    let isRunning: Bool
    let destinationsEmpty: Bool
    var onRemove: (() -> Void)? = nil
    let onBackup: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let onRemove {
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .disabled(isRunning)
            }

            Button("Backup") { onBackup() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunning || destinationsEmpty)
        }
        .padding(.vertical, 2)
    }
}
