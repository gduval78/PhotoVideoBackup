import SwiftUI

/// The Backups tab (2.7.0): the user's backup profiles, one card each, one tap to run.
/// The progress card and the completion banner are the same views the Advanced dashboard uses.
struct BackupsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager
    @Environment(StoreManager.self)       private var store
    @State private var showPaywall = false
    @State private var profileStore = ProfileStore.shared
    @State private var showNew = false
    @State private var renaming: BackupProfile?
    @State private var renameText = ""
    @State private var deleting: BackupProfile?
    @State private var editing: BackupProfile?
    /// The backup whose summary (source → destinations) is shown before it runs.
    @State private var summarizing: BackupProfile?
    /// What the folder picker is reconnecting: a card/drive source or a destination folder.
    private enum Reconnect { case source(UUID), folder(String) }
    @State private var reconnecting: Reconnect?
    @State private var showImporter = false
    @State private var connections: [UUID: DashboardViewModel.ProfileConnection] = [:]

    var body: some View {
        List {
            if !profileStore.profiles.isEmpty {
                Section {
                    ForEach(Array(profileStore.profiles.enumerated()), id: \.element.id) { index, profile in
                        ProfileCard(profile: profile,
                                    locked: !ProfileStore.isAllowed(index: index, isPremium: store.isPremium),
                                    onUnlock: { showPaywall = true },
                                    sourceName: sourceName(for: profile),
                                    connection: connections[profile.id],
                                    transfer: .of(isRemote: profile.usesNAS || profile.usesWebDAV || (connections[profile.id]?.hasCloudFolder ?? false),
                                                  isCellular: viewModel.isLikelyCellular),
                                    sourceAvailable: sourceAvailable(for: profile),
                                    isRunning: viewModel.isRunning,
                                    onRun: { summarizing = profile },
                                    onRename: { renameText = profile.name; renaming = profile },
                                    onSettings: { editing = profile },
                                    onReconnect: { startReconnect(profile) },
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
                Button { newBackup() } label: { Image(systemName: "plus") }
                    .disabled(viewModel.isRunning)
                    .accessibilityLabel(Text("New backup"))
            }
        }
        .sheet(isPresented: $showNew, onDismiss: refreshConnections) { NewBackupFlow() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $summarizing) { profile in
            BackupSummarySheet(profile: profile,
                               sourceName: sourceName(for: profile),
                               destinationNames: connections[profile.id]?.destinationNames ?? [],
                               onStart: { Task { await viewModel.runProfile(profile) } })
        }
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
                if let p = deleting { delete(p) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The backup settings are removed. Files already copied are not affected.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { reconnecting = nil; return }
            finishReconnect(url)
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
                Button { newBackup() } label: {
                    Label("New backup", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// The free version has one backup: a second one opens the upgrade screen instead.
    private func newBackup() {
        if ProfileStore.canAdd(count: profileStore.profiles.count, isPremium: store.isPremium) { showNew = true }
        else { showPaywall = true }
    }

    private func refreshConnections() {
        var map: [UUID: DashboardViewModel.ProfileConnection] = [:]
        for p in profileStore.profiles { map[p.id] = viewModel.connection(of: p) }
        connections = map
    }

    /// Deleting a backup also forgets a camera card / drive that no other backup uses.
    private func delete(_ profile: BackupProfile) {
        profileStore.delete(profile.id)
        connections[profile.id] = nil
        if case .external(let id) = profile.source,
           !profileStore.profiles.contains(where: { $0.source == .external(id) }) {
            viewModel.removeExternalSource(id: id)
        }
    }

    /// The card shows a *Reconnect* button when its source or one of its folders cannot be reached.
    private func startReconnect(_ profile: BackupProfile) {
        if case .external(let id) = profile.source, !sourceAvailable(for: profile) {
            reconnecting = .source(id)
        } else if let key = connections[profile.id]?.disconnectedFolderKey {
            reconnecting = .folder(key)
        } else { return }
        if ProcessInfo.processInfo.isiOSAppOnMac {
            guard let url = MacOpenPanel.pickFolder() else { reconnecting = nil; return }
            finishReconnect(url)
        } else {
            showImporter = true
        }
    }

    private func finishReconnect(_ url: URL) {
        defer { reconnecting = nil; refreshConnections() }
        switch reconnecting {
        case .source(let id):
            // The bookmark must be made right here, while the picker's access is active.
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            url.stopAccessingSecurityScopedResource()
            if let bookmark { viewModel.reconnectSource(id: id, url: url, bookmarkData: bookmark) }
        case .folder(let key):
            DestinationManager.shared.saveBookmark(url: url, forKey: key)
        case nil:
            break
        }
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
    @Environment(LanguageManager.self) private var languageManager
    let profile: BackupProfile
    let locked: Bool
    let onUnlock: () -> Void
    let sourceName: String
    let connection: DashboardViewModel.ProfileConnection?
    let transfer: TransferKind
    let sourceAvailable: Bool
    let isRunning: Bool
    let onRun: () -> Void
    let onRename: () -> Void
    let onSettings: () -> Void
    let onReconnect: () -> Void
    let onDelete: () -> Void

    private var destinations: String { connection?.destinationNames.joined(separator: ", ") ?? "" }
    private var ready: Bool { (connection?.isConnected ?? false) && sourceAvailable }

    var body: some View {
        HStack(spacing: 12) {
            // Main pictogram (drive / card / cloud) + a badge for the transfer type: local cable,
            // Wi-Fi, or mobile data (SIM / eSIM).
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: profile.template.symbol(hasCloudFolder: connection?.hasCloudFolder ?? false))
                    .font(.title2).foregroundStyle(ready ? Color.accentColor : .secondary)
                    .frame(width: 34, height: 30)
                Image(systemName: transfer.badgeSymbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(transfer == .cellular ? Color.orange : (ready ? Color.accentColor : .secondary))
                    .padding(2)
                    .background(Circle().fill(Color(.systemBackground)))
                    .offset(x: 5, y: 4)
            }
            .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: profile.name).font(.headline)
                Text(verbatim: "\(sourceName) → \(destinations)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if !ready {
                    Text("Not connected").font(.caption2).foregroundStyle(.orange)
                } else if let free = connection?.freeBytes {
                    // Free space of the fullest destination, so a nearly full drive is seen before a run.
                    HStack(spacing: 6) {
                        Text("\(free.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))) free")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let used = connection?.usedFraction {
                            ProgressView(value: used).tint(used > 0.9 ? .red : .accentColor).frame(maxWidth: 80)
                        }
                    }
                }
            }
            Spacer()
            if locked {
                Button { onUnlock() } label: { Label("Unlock", systemImage: "lock.fill") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if ready {
                Button("Run", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRunning)
            } else {
                Button("Reconnect", action: onReconnect)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunning)
            }
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
