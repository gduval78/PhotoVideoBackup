import SwiftUI

/// The Backups tab (2.7.0): the user's backup profiles, one card each, one tap to run.
/// The progress card and the completion banner are the same views the Advanced dashboard uses.
struct BackupsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager
    @State private var profileStore = ProfileStore.shared
    @State private var showNew = false
    @State private var renaming: BackupProfile?
    @State private var renameText = ""
    @State private var deleting: BackupProfile?
    @State private var editing: BackupProfile?
    @State private var connections: [UUID: DashboardViewModel.ProfileConnection] = [:]

    var body: some View {
        List {
            if !profileStore.profiles.isEmpty {
                Section {
                    ForEach(profileStore.profiles) { profile in
                        ProfileCard(profile: profile,
                                    sourceName: sourceName(for: profile),
                                    connection: connections[profile.id],
                                    sourceAvailable: sourceAvailable(for: profile),
                                    isRunning: viewModel.isRunning,
                                    onRun: { Task { await viewModel.runProfile(profile) } },
                                    onRename: { renameText = profile.name; renaming = profile },
                                    onSettings: { editing = profile },
                                    onDelete: { deleting = profile })
                    }
                }
            }
            if !viewModel.isRunning, let banner = viewModel.completionBanner {
                CompletionBannerSection(banner: banner)
            }
        }
        .overlay {
            if profileStore.profiles.isEmpty { emptyState }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isRunning {
                SessionProgressView()
                    .padding(.top, 8)
                    .background(.regularMaterial)
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .disabled(viewModel.isRunning)
                    .accessibilityLabel(Text("New backup"))
            }
        }
        .sheet(isPresented: $showNew, onDismiss: refreshConnections) { NewBackupFlow() }
        .sheet(item: $editing, onDismiss: refreshConnections) { profile in
            NavigationStack { ProfileDetailView(profile: profile) }
        }
        .alert("Rename backup", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let p = renaming { profileStore.rename(p.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Delete this backup?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let p = deleting { profileStore.delete(p.id); connections[p.id] = nil }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The backup settings are removed. Files already copied are not affected.")
        }
        .onAppear { refreshConnections() }
        .onChange(of: viewModel.isRunning) { _, running in if !running { refreshConnections() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshConnections()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 44)).foregroundStyle(.tint)
                Text("Create your first backup").font(.headline)
                Text("Choose what to back up and where. Then one tap is all it takes.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { showNew = true } label: {
                    Label("New backup", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func refreshConnections() {
        var map: [UUID: DashboardViewModel.ProfileConnection] = [:]
        for p in profileStore.profiles { map[p.id] = viewModel.connection(of: p) }
        connections = map
    }

    private func sourceName(for profile: BackupProfile) -> String {
        switch profile.source {
        case .photos: return String(localized: "Photos Library", locale: languageManager.currentLocale)
        case .external(let id): return viewModel.externalSources.first { $0.id == id }?.displayName ?? "—"
        }
    }

    private func sourceAvailable(for profile: BackupProfile) -> Bool {
        switch profile.source {
        case .photos: return true
        case .external(let id): return viewModel.externalSources.first { $0.id == id }?.isAvailable ?? false
        }
    }
}

// MARK: - Card

private struct ProfileCard: View {
    let profile: BackupProfile
    let sourceName: String
    let connection: DashboardViewModel.ProfileConnection?
    let sourceAvailable: Bool
    let isRunning: Bool
    let onRun: () -> Void
    let onRename: () -> Void
    let onSettings: () -> Void
    let onDelete: () -> Void

    private var destinations: String { connection?.destinationNames.joined(separator: ", ") ?? "" }
    private var ready: Bool { (connection?.isConnected ?? false) && sourceAvailable }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.template.symbol)
                .font(.title2).foregroundStyle(ready ? Color.accentColor : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: profile.name).font(.headline)
                Text(verbatim: "\(sourceName) → \(destinations)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !ready {
                    Text("Not connected").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Run", action: onRun)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRunning || !ready)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Settings", systemImage: "gearshape", action: onSettings)
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Settings", action: onSettings).tint(.gray)
            Button("Rename", action: onRename).tint(.blue)
        }
    }
}
