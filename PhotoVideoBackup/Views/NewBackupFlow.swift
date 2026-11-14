import SwiftUI

/// "New backup": pick a template, choose the drive / folder once, name it. No technical vocabulary.
struct NewBackupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @State private var path: [ProfileTemplate] = []
    @State private var showPaywall = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(ProfileTemplate.selectable, id: \.self) { template in
                        Button {
                            if template.requiresPro && !store.isPremium { showPaywall = true }
                            else { path.append(template) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.symbol)
                                    .font(.title3).foregroundStyle(Color.accentColor).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.titleKey).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(template.detailKey).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if template.requiresPro && !store.isPremium {
                                    Text("Pro").font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Choose a starting point. You pick the drive or folder in the next step.")
                }
            }
            .navigationTitle("New backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: ProfileTemplate.self) { template in
                NewBackupSetup(template: template) { dismiss() }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }
}

// MARK: - Setup step

private struct NewBackupSetup: View {
    let template: ProfileTemplate
    let onDone: () -> Void

    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager

    /// Fixed up front: the folder bookmark is saved under this id's key as soon as it is picked.
    @State private var profileID = UUID()
    @State private var name = ""
    @State private var folderLabel: String?
    @State private var sourceID: UUID?
    @State private var showImporter = false
    @State private var pickTarget: PickTarget = .destination
    @State private var created = false
    @AppStorage("deviceName") private var deviceName: String = ""

    private enum PickTarget { case destination, source }

    private var folderKey: String { BackupProfile.folderKey(profileID: profileID, index: 0) }
    private var nasConfigured: Bool { DestinationManager.shared.isNASConfigured() }
    private var availableSources: [ExternalSource] { viewModel.externalSources.filter(\.isAvailable) }

    /// A photo-library backup is filed under the device name; without one the engine refuses to
    /// start, so the flow asks for it here instead of failing at the first Run.
    private var needsDeviceName: Bool {
        !template.usesExternalSource && deviceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !needsDeviceName
            && (template.folderCount == 0 || folderLabel != nil)
            && (!template.usesExternalSource || sourceID != nil)
            && (!template.includesNAS || nasConfigured)
    }

    var body: some View {
        Form {
            if template.usesExternalSource { sourceSection }
            if template.folderCount > 0 { destinationSection }
            if template.includesNAS { nasSection }
            if !template.usesExternalSource { deviceNameSection }
            Section("Name") {
                TextField("Name", text: $name)
            }
        }
        .navigationTitle(template.titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { create() }.disabled(!canCreate)
            }
        }
        .onAppear {
            if name.isEmpty { name = template.defaultName }
            if sourceID == nil { sourceID = availableSources.first?.id }
        }
        .onDisappear {
            // Backed out without creating: forget the folder picked for this attempt.
            if !created { DestinationManager.shared.clearBookmark(forKey: folderKey) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            handlePicked(url)
        }
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

    private var destinationSection: some View {
        Section {
            LabeledContent("Destination") {
                if let folderLabel {
                    Text(verbatim: folderLabel).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Not chosen").foregroundStyle(.tertiary)
                }
            }
            Button("Choose…") { pick(.destination) }
        } header: {
            Text("Destination")
        } footer: {
            switch template {
            case .photosToICloud, .driveToICloud:
                Text("Pick a folder in iCloud Drive (Files → iCloud Drive). iCloud is slow and depends on iOS and your iCloud space.")
            default:
                Text("Connect your drive, then pick the folder to back up into. You can create a folder in the picker.")
            }
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

    private var nasSection: some View {
        Section("NAS") {
            if nasConfigured, let cfg = DestinationManager.shared.loadNASConfig() {
                Label { Text(verbatim: cfg.label) } icon: { Image(systemName: "server.rack") }
            } else {
                Label("Set up your NAS in Settings first, then come back.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.subheadline)
            }
        }
    }

    // MARK: Actions

    private func pick(_ target: PickTarget) {
        pickTarget = target
        if ProcessInfo.processInfo.isiOSAppOnMac {
            guard let url = MacOpenPanel.pickFolder() else { return }
            handlePicked(url)
        } else {
            showImporter = true
        }
    }

    private func handlePicked(_ url: URL) {
        switch pickTarget {
        case .destination:
            let dm = DestinationManager.shared
            dm.saveBookmark(url: url, forKey: folderKey)
            let volume = dm.displayName(forKey: folderKey)
            let folder = dm.folderName(forKey: folderKey)
            folderLabel = [volume, folder].filter { !$0.isEmpty }.joined(separator: " / ")
            if folderLabel?.isEmpty ?? true { folderLabel = url.lastPathComponent }
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

    private func create() {
        var destinations: [ProfileDestination] = []
        if template.folderCount > 0 { destinations.append(.folder(bookmarkKey: folderKey)) }
        if template.includesNAS { destinations.append(.nas) }
        let source: ProfileSource = template.usesExternalSource ? .external(sourceID ?? UUID()) : .photos
        let profile = BackupProfile(id: profileID,
                                    name: name.trimmingCharacters(in: .whitespaces),
                                    template: template, source: source, destinations: destinations)
        ProfileStore.shared.add(profile)
        created = true
        onDone()
    }
}
