import SwiftUI

/// A backup's editor — used to **create** a backup (after choosing what to back up) and to **edit** one:
/// its name, its destinations (any number of **folders** and **servers**; a server's type — NAS, WebDAV… —
/// is chosen when it is added and its form follows the typed connection), and its own options. Edited as a
/// copy and saved at once, so cancelling leaves the backup exactly as it was.
struct ProfileDetailView: View {
    let original: BackupProfile
    /// Creating a new backup (not yet stored) rather than editing one.
    var isNew = false
    /// Called after Save / Cancel when the editor is shown inside a flow that must close itself.
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self) private var store
    @AppStorage("deviceName") private var deviceName: String = ""

    @State private var profile: BackupProfile
    @State private var settings: ProfileSettings
    /// Passwords being edited, by server id (they reach the Keychain only on Save).
    @State private var passwords: [UUID: String] = [:]
    @State private var sourceID: UUID?
    private enum PickTarget { case destination, source }
    @State private var pickTarget: PickTarget = .destination
    /// Which folder row the importer is choosing for, or nil when it adds a new destination.
    @State private var pickingIndex: Int?
    @State private var showImporter = false
    @State private var showPaywall = false
    @State private var showOverlapAlert = false

    init(profile: BackupProfile, isNew: Bool = false, onDone: (() -> Void)? = nil) {
        self.original = profile
        self.isNew = isNew
        self.onDone = onDone
        _profile = State(initialValue: profile)
        _settings = State(initialValue: profile.settings ?? ProfileSettings.fromGlobal())
    }

    private var availableSources: [ExternalSource] { viewModel.externalSources.filter(\.isAvailable) }

    private var needsDeviceName: Bool {
        isNew && !profile.usesExternalSource && deviceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !profile.destinations.isEmpty
            && profile.servers.allSatisfy { $0.connection.isComplete }
            && !needsDeviceName
            && (!isNew || !profile.usesExternalSource || sourceID != nil)
    }

    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $profile.name) }

            if isNew && profile.usesExternalSource { sourceSection }

            destinationsSection

            ForEach(profile.servers) { server in
                ServerEditor(connection: connectionBinding(server.id), password: passwordBinding(server.id))
            }

            if isNew && !profile.usesExternalSource { deviceNameSection }

            ProfileOptionsForm(settings: $settings)
        }
        .navigationTitle(isNew ? Text("New backup") : Text(verbatim: original.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save") { save() }.disabled(!canSave)
            }
        }
        .navigationBarBackButtonHidden(isNew)
        .onAppear {
            for server in profile.servers where passwords[server.id] == nil {
                passwords[server.id] = KeychainStore.get(account: server.passwordAccount ?? "") ?? ""
            }
            if isNew, profile.usesExternalSource, sourceID == nil { sourceID = availableSources.first?.id }
            if isNew, profile.name.isEmpty { profile.name = defaultName }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            handlePicked(url)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("This folder overlaps another destination", isPresented: $showOverlapAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a folder that is not inside another destination of this backup and does not contain one: the files would be written twice in the same place.")
        }
    }

    /// The name pre-filled for a new backup, from its source.
    private var defaultName: String {
        profile.usesExternalSource ? String(localized: "Camera backup") : String(localized: "Photos backup")
    }

    // MARK: Bindings

    private func connectionBinding(_ id: UUID) -> Binding<ServerConnection> {
        Binding(
            get: { profile.servers.first { $0.id == id }?.connection ?? .unknown(type: "", fields: [:]) },
            set: { new in
                guard let i = profile.destinations.firstIndex(where: { $0.serverDestination?.id == id }),
                      case .server(var server) = profile.destinations[i] else { return }
                server.connection = new
                profile.destinations[i] = .server(server)
            })
    }

    private func passwordBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { passwords[id] ?? "" }, set: { passwords[id] = $0 })
    }

    // MARK: Sections

    private var sourceSection: some View {
        Section {
            if availableSources.isEmpty {
                Text("No camera card or drive added yet.").foregroundStyle(.secondary)
            } else {
                Picker("Source", selection: $sourceID) {
                    ForEach(availableSources) { s in Text(verbatim: s.displayName).tag(Optional(s.id)) }
                }
            }
            Button("Add a source…") { pick(.source) }
        } header: {
            Text("Source")
        } footer: {
            Text("Choose the folder of the card or drive to copy from. For a drive that already holds a backup, choose the device folder inside it.")
        }
    }

    private var deviceNameSection: some View {
        Section {
            TextField("e.g. Gerard's iPhone", text: $deviceName)
        } header: {
            Text("Folder name")
        } footer: {
            Text("Your backups are saved in a folder with this name.")
        }
    }

    private var destinationsSection: some View {
        Section {
            ForEach(Array(profile.destinations.enumerated()), id: \.offset) { index, destination in
                switch destination {
                case .folder:
                    VStack(alignment: .leading, spacing: 6) {
                        Label { Text(verbatim: label(of: destination)) } icon: { Image(systemName: "externaldrive.fill") }
                        Button("Choose another folder…") { pick(.destination, replacing: index) }
                            .font(.callout)
                    }
                case .server(let server):
                    Label {
                        Text(verbatim: server.connection.isComplete ? server.connection.label : (server.connection.kind.map(titleString) ?? String(localized: "Server")))
                    } icon: { Image(systemName: server.connection.symbol) }
                }
            }
            .onDelete { offsets in remove(at: offsets) }
            .deleteDisabled(!isNew && profile.destinations.count <= 1)

            Menu {
                Button("A folder…") { addFolder() }
                Menu("A server") {
                    ForEach(ServerKind.allCases) { kind in
                        Button { addServer(kind) } label: { Text(kind.titleKey) }
                    }
                }
            } label: {
                Label("Add a destination", systemImage: "plus.circle")
            }
        } header: {
            Text("Destinations")
        } footer: {
            Text("A backup can copy to several destinations at once. A folder is a drive, a card, or any folder in the Files app (iCloud Drive, Google Drive…). A server is reached by an address and an account (a NAS, Nextcloud, pCloud…). Swipe to remove a destination.")
        }
    }

    private func titleString(_ kind: ServerKind) -> String {
        switch kind {
        case .smb:    return String(localized: "NAS")
        case .webdav: return String(localized: "WebDAV server")
        case .pcloud: return "pCloud"
        }
    }

    private func label(of destination: ProfileDestination) -> String {
        guard case .folder(let key) = destination else { return "" }
        let dm = DestinationManager.shared
        let text = [dm.displayName(forKey: key), dm.folderName(forKey: key)]
            .filter { !$0.isEmpty }.joined(separator: " / ")
        return text.isEmpty ? "—" : text
    }

    // MARK: Adding and removing destinations

    /// A server, or a second destination, is a Pro feature, as everywhere else in the app.
    private func requirePro(forServer: Bool) -> Bool {
        guard !store.isPremium, forServer || !profile.destinations.isEmpty else { return true }
        showPaywall = true
        return false
    }

    private func addFolder() {
        guard requirePro(forServer: false) else { return }
        pick(.destination, replacing: nil)
    }

    private func addServer(_ kind: ServerKind) {
        guard requirePro(forServer: true) else { return }
        let server = ServerDestination(connection: kind.emptyConnection)
        passwords[server.id] = ""
        profile.destinations.append(.server(server))
    }

    private func remove(at offsets: IndexSet) {
        if !isNew { guard profile.destinations.count - offsets.count >= 1 else { return } }
        profile.destinations.remove(atOffsets: offsets)
    }

    // MARK: Picking folders

    private func pick(_ target: PickTarget, replacing index: Int? = nil) {
        pickTarget = target
        pickingIndex = index
        if ProcessInfo.processInfo.isiOSAppOnMac {
            guard let url = MacOpenPanel.pickFolder() else { return }
            handlePicked(url)
        } else {
            showImporter = true
        }
    }

    private func handlePicked(_ url: URL) {
        switch pickTarget {
        case .destination: applyFolder(url)
        case .source:
            // The bookmark must be made right here, while the picker's security scope is active.
            _ = url.startAccessingSecurityScopedResource()
            let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            url.stopAccessingSecurityScopedResource()
            guard let bookmark else { return }
            viewModel.addExternalSource(url: url, bookmarkData: bookmark, customName: nil)
            sourceID = viewModel.externalSources.first { $0.rootURL == url }?.id ?? availableSources.last?.id
        }
    }

    /// Saves the bookmark right away (the picker's access is only valid here) under a key of this
    /// session; it is kept or discarded when the user saves or cancels.
    private func applyFolder(_ url: URL) {
        // The other destinations of this backup (not the one being replaced): the new folder must be
        // independent of all of them.
        let dm = DestinationManager.shared
        let others = profile.destinations.enumerated().compactMap { offset, destination -> URL? in
            guard offset != pickingIndex, case .folder(let key) = destination else { return nil }
            return dm.resolveBookmark(forKey: key)
        }
        if ProfileStore.overlaps(url, with: others) {
            pickingIndex = nil
            showOverlapAlert = true
            return
        }
        // A key nothing else uses: not one of this backup's folders (stored or picked just now), and no
        // bookmark saved under it — otherwise the new folder would overwrite another one.
        let key = BackupProfile.uniqueFolderKey(profileID: profile.id) { candidate in
            profile.folderKeys.contains(candidate) || original.folderKeys.contains(candidate)
                || dm.isConfigured(forKey: candidate)
        }
        dm.saveBookmark(url: url, forKey: key)
        if let index = pickingIndex, profile.destinations.indices.contains(index) {
            profile.destinations[index] = .folder(bookmarkKey: key)
        } else {
            profile.destinations.append(.folder(bookmarkKey: key))
        }
        pickingIndex = nil
    }

    // MARK: Cancel / Save

    /// Keys this edit created (not in the stored profile) — forgotten on cancel.
    private var sessionKeys: [String] {
        profile.folderKeys.filter { !original.folderKeys.contains($0) }
    }

    private func finish() { if let onDone { onDone() } else { dismiss() } }

    private func cancel() {
        for key in sessionKeys { DestinationManager.shared.clearBookmark(forKey: key) }
        finish()
    }

    private func isOwnAccount(_ account: String?) -> Bool {
        guard let account else { return false }
        return account.hasPrefix("profile.") || account.hasPrefix("server.")
    }

    private func save() {
        var edited = profile
        edited.name = profile.name.trimmingCharacters(in: .whitespaces)
        edited.settings = settings
        if isNew, profile.usesExternalSource, let sourceID { edited.source = .external(sourceID) }
        // Folders that were replaced or removed: a profile-owned one is forgotten, a legacy (shared)
        // key is left alone.
        for old in original.folderKeys where !edited.folderKeys.contains(old) && old.hasPrefix("PhotoVideoBackup.profile.") {
            DestinationManager.shared.clearBookmark(forKey: old)
        }
        // Servers: the connection is saved trimmed, and the password now belongs to this backup (its own
        // Keychain account), whatever account it came from. A removed server's password is forgotten.
        for (i, destination) in edited.destinations.enumerated() {
            guard case .server(var server) = destination else { continue }
            server.connection = server.connection.normalized
            let account = isOwnAccount(server.passwordAccount) ? server.passwordAccount! : ServerDestination.passwordAccount(for: server.id)
            KeychainStore.set(passwords[server.id] ?? "", account: account)
            server.passwordAccount = account
            edited.destinations[i] = .server(server)
        }
        let keptIDs = Set(edited.servers.map(\.id))
        for old in original.servers where !keptIDs.contains(old.id) && isOwnAccount(old.passwordAccount) {
            KeychainStore.delete(account: old.passwordAccount!)
        }
        if isNew { ProfileStore.shared.add(edited) } else { ProfileStore.shared.update(edited) }
        finish()
    }
}
