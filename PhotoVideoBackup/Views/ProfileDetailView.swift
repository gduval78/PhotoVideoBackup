import SwiftUI

/// A backup's settings: its name, its destinations (any number of folders and a NAS), its own NAS and
/// its own options. Edited as a copy and saved at once, so cancelling leaves the backup exactly as it was.
struct ProfileDetailView: View {
    let original: BackupProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self) private var store

    @State private var profile: BackupProfile
    @State private var settings: ProfileSettings
    @State private var nasConfig: NASConfig
    @State private var nasPassword = ""
    /// Which folder row the importer is choosing for, or nil when it adds a new destination.
    @State private var pickingIndex: Int?
    @State private var showImporter = false
    @State private var showPaywall = false
    /// Next number for the keys of folders picked in this session (never collides with stored ones).
    @State private var nextKeyIndex = 100

    init(profile: BackupProfile) {
        self.original = profile
        _profile = State(initialValue: profile)
        _settings = State(initialValue: profile.settings ?? ProfileSettings.fromGlobal())
        _nasConfig = State(initialValue: profile.nas ?? DestinationManager.shared.loadNASConfig() ?? .empty)
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !profile.destinations.isEmpty
            && (!profile.usesNAS || nasConfig.isComplete)
    }

    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $profile.name) }

            destinationsSection

            if profile.usesNAS {
                ProfileNASEditor(config: $nasConfig, password: $nasPassword)
            }

            ProfileOptionsForm(settings: $settings)
        }
        .navigationTitle(Text(verbatim: original.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
        }
        .onAppear {
            if profile.usesNAS {
                let account = original.nasPasswordAccount ?? DestinationManager.shared.legacyNASPasswordAccount
                nasPassword = KeychainStore.get(account: account) ?? ""
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            apply(url)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Destinations

    private var destinationsSection: some View {
        Section {
            ForEach(Array(profile.destinations.enumerated()), id: \.offset) { index, destination in
                switch destination {
                case .folder:
                    VStack(alignment: .leading, spacing: 6) {
                        Label { Text(verbatim: label(of: destination)) } icon: { Image(systemName: "externaldrive.fill") }
                        Button("Choose another folder…") { pick(replacing: index) }
                            .font(.callout)
                    }
                case .nas:
                    Label {
                        Text(verbatim: nasConfig.isComplete ? nasConfig.label : String(localized: "NAS"))
                    } icon: { Image(systemName: "server.rack") }
                }
            }
            .onDelete { offsets in remove(at: offsets) }
            .deleteDisabled(profile.destinations.count <= 1)

            Menu {
                Button("Another folder…") { addFolder() }
                if !profile.usesNAS { Button("A NAS") { addNAS() } }
            } label: {
                Label("Add a destination", systemImage: "plus.circle")
            }
        } header: {
            Text("Destinations")
        } footer: {
            Text("A backup can copy to several destinations at once. Swipe to remove one. Choosing another folder is for a replaced drive or an access that no longer works — files already copied stay where they are.")
        }
    }

    private func label(of destination: ProfileDestination) -> String {
        guard case .folder(let key) = destination else { return "NAS" }
        let dm = DestinationManager.shared
        let text = [dm.displayName(forKey: key), dm.folderName(forKey: key)]
            .filter { !$0.isEmpty }.joined(separator: " / ")
        return text.isEmpty ? "—" : text
    }

    /// A second destination is a Pro feature, as everywhere else in the app.
    private func requirePro() -> Bool {
        guard profile.destinations.count >= 1, !store.isPremium else { return true }
        showPaywall = true
        return false
    }

    private func addFolder() {
        guard requirePro() else { return }
        pickingIndex = nil
        pickFolder()
    }

    private func addNAS() {
        guard requirePro() else { return }
        nasConfig = .empty
        nasPassword = ""
        profile.destinations.append(.nas)
    }

    private func pick(replacing index: Int) {
        pickingIndex = index
        pickFolder()
    }

    private func pickFolder() {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            guard let url = MacOpenPanel.pickFolder() else { return }
            apply(url)
        } else {
            showImporter = true
        }
    }

    /// Saves the bookmark right away (the picker's access is only valid here) under a key of this
    /// session; it is kept or discarded when the user saves or cancels.
    private func apply(_ url: URL) {
        let key = BackupProfile.folderKey(profileID: profile.id, index: nextKeyIndex)
        nextKeyIndex += 1
        DestinationManager.shared.saveBookmark(url: url, forKey: key)
        if let index = pickingIndex, profile.destinations.indices.contains(index) {
            profile.destinations[index] = .folder(bookmarkKey: key)
        } else {
            profile.destinations.append(.folder(bookmarkKey: key))
        }
        pickingIndex = nil
    }

    private func remove(at offsets: IndexSet) {
        guard profile.destinations.count - offsets.count >= 1 else { return }
        profile.destinations.remove(atOffsets: offsets)
    }

    // MARK: Cancel / Save

    /// Keys this edit created (not in the stored profile) — forgotten on cancel.
    private var sessionKeys: [String] {
        profile.folderKeys.filter { !original.folderKeys.contains($0) }
    }

    private func cancel() {
        for key in sessionKeys { DestinationManager.shared.clearBookmark(forKey: key) }
        dismiss()
    }

    private func save() {
        var edited = profile
        edited.name = profile.name.trimmingCharacters(in: .whitespaces)
        edited.settings = settings
        // Folders that were replaced or removed: a profile-owned one is forgotten, a legacy (shared)
        // key is left alone.
        for old in original.folderKeys where !edited.folderKeys.contains(old) && old.hasPrefix("PhotoVideoBackup.profile.") {
            DestinationManager.shared.clearBookmark(forKey: old)
        }
        if edited.usesNAS {
            var cleaned = nasConfig
            cleaned.host = nasConfig.host.trimmingCharacters(in: .whitespaces)
            cleaned.share = nasConfig.share.trimmingCharacters(in: .whitespaces)
            cleaned.basePath = nasConfig.basePath.trimmingCharacters(in: .whitespaces)
            cleaned.username = nasConfig.username.trimmingCharacters(in: .whitespaces)
            cleaned.displayName = nasConfig.displayName.trimmingCharacters(in: .whitespaces)
            // The password now belongs to this backup, whatever account it came from.
            let account = BackupProfile.nasPasswordAccount(profileID: edited.id)
            KeychainStore.set(nasPassword, account: account)
            edited.nas = cleaned
            edited.nasPasswordAccount = account
        } else {
            // The NAS was removed from this backup: forget its own password too.
            if let account = original.nasPasswordAccount, account.hasPrefix("profile.") {
                KeychainStore.delete(account: account)
            }
            edited.nas = nil
            edited.nasPasswordAccount = nil
        }
        ProfileStore.shared.update(edited)
        dismiss()
    }
}
