import SwiftUI

/// A backup's settings: its name, its folder(s), its own NAS and its own options. Edited as a copy and
/// saved at once, so cancelling leaves the backup exactly as it was.
struct ProfileDetailView: View {
    let original: BackupProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(DashboardViewModel.self) private var viewModel

    @State private var profile: BackupProfile
    @State private var settings: ProfileSettings
    @State private var nasConfig: NASConfig
    @State private var nasPassword = ""
    /// Folders picked in this session, by destination index → the staging key holding the new bookmark.
    @State private var stagedKeys: [Int: String] = [:]
    @State private var stagedLabels: [Int: String] = [:]
    @State private var pickingIndex = 0
    @State private var showImporter = false

    init(profile: BackupProfile) {
        self.original = profile
        _profile = State(initialValue: profile)
        _settings = State(initialValue: profile.settings ?? ProfileSettings.fromGlobal())
        _nasConfig = State(initialValue: profile.nas ?? DestinationManager.shared.loadNASConfig() ?? .empty)
    }

    private var folderIndices: [Int] {
        profile.destinations.enumerated().compactMap { if case .folder = $0.element { return $0.offset } else { return nil } }
    }

    private var canSave: Bool {
        !profile.name.trimmingCharacters(in: .whitespaces).isEmpty && (!profile.usesNAS || nasConfig.isComplete)
    }

    var body: some View {
        Form {
            Section("Name") { TextField("Name", text: $profile.name) }

            ForEach(folderIndices, id: \.self) { index in
                Section {
                    LabeledContent("Destination") {
                        Text(verbatim: label(forFolderAt: index)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button("Choose another folder…") { pick(index) }
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Use this when you replace the drive or its access no longer works. Files already copied stay where they are.")
                }
            }

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
            stage(url, at: pickingIndex)
        }
    }

    // MARK: Folder change

    private func label(forFolderAt index: Int) -> String {
        if let staged = stagedLabels[index] { return staged }
        guard case .folder(let key) = profile.destinations[index] else { return "" }
        let dm = DestinationManager.shared
        let volume = dm.displayName(forKey: key)
        let folder = dm.folderName(forKey: key)
        let text = [volume, folder].filter { !$0.isEmpty }.joined(separator: " / ")
        return text.isEmpty ? "—" : text
    }

    private func pick(_ index: Int) {
        pickingIndex = index
        if ProcessInfo.processInfo.isiOSAppOnMac {
            guard let url = MacOpenPanel.pickFolder() else { return }
            stage(url, at: index)
        } else {
            showImporter = true
        }
    }

    /// Saves the new bookmark under a staging key now (the picker's access is only valid right here);
    /// it becomes the backup's folder only when the user saves.
    private func stage(_ url: URL, at index: Int) {
        let dm = DestinationManager.shared
        let key = BackupProfile.folderKey(profileID: profile.id, index: 50 + index)
        dm.saveBookmark(url: url, forKey: key)
        stagedKeys[index] = key
        let volume = dm.displayName(forKey: key)
        let folder = dm.folderName(forKey: key)
        stagedLabels[index] = [volume, folder].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private func cancel() {
        for key in stagedKeys.values { DestinationManager.shared.clearBookmark(forKey: key) }
        dismiss()
    }

    // MARK: Save

    private func save() {
        var edited = profile
        edited.name = profile.name.trimmingCharacters(in: .whitespaces)
        edited.settings = settings
        for (index, key) in stagedKeys {
            // A profile-owned folder it replaces is forgotten; a legacy (shared) key is left alone.
            if case .folder(let old) = edited.destinations[index], old.hasPrefix("PhotoVideoBackup.profile.") {
                DestinationManager.shared.clearBookmark(forKey: old)
            }
            edited.destinations[index] = .folder(bookmarkKey: key)
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
        }
        ProfileStore.shared.update(edited)
        viewModel.refreshDestinationStatuses()
        dismiss()
    }
}
