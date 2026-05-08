import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @State private var ssd1Name:   String = ""
    @State private var ssd2Name:   String = ""
    @State private var ssd3Name:   String = ""
    @State private var ssd1Folder: String = ""
    @State private var ssd2Folder: String = ""
    @State private var ssd3Folder: String = ""
    @State private var showPicker: Bool = false
    @State private var pickerIndex: Int = 0
    @State private var showPaywall: Bool = false
    @AppStorage("deviceName") private var deviceName: String = ""
    @AppStorage("folderOrganization") private var folderOrganizationRaw: String = FolderOrganization.byDate.rawValue
    @AppStorage("backupFileLimit") private var backupFileLimit: Int = 0
    @AppStorage("customExtensions") private var customExtensionsRaw: String = ""

    var body: some View {
        List {
            Section("iPhone / iPad") {
                HStack {
                    Text("Folder name")
                    Spacer()
                    TextField("e.g. Gerard's iPhone", text: $deviceName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Backup") {
                Picker("Folder structure", selection: $folderOrganizationRaw) {
                    ForEach(FolderOrganization.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                HStack {
                    Text("Max files per session")
                    Spacer()
                    TextField("Unlimited", value: $backupFileLimit, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                }
                NavigationLink {
                    CustomExtensionsView()
                } label: {
                    HStack {
                        Text("Additional file types")
                        Spacer()
                        Text(customExtensionsLabel)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }

            Section("Destinations") {
                destinationRow(index: 0, name: $ssd1Name, folder: $ssd1Folder, label: "SSD 1 (primary)")
                ssd2Row
                ssd3Row
            }

            Section {
                Text("Connect your USB-C SSD or SD card, then tap Choose… to select the destination folder. You can create a new folder directly in the Files picker before selecting it. Access is preserved across launches via secure bookmarks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PhotoVideoBackup")
                            .font(.headline)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadNames() }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let dm = DestinationManager.shared
            dm.saveBookmark(url: url, forKey: dm.key(for: pickerIndex))
            loadNames()
            viewModel.refreshDestinationStatuses()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - SSD 2 / SD Card rows (Pro only)

    @ViewBuilder
    private var ssd2Row: some View {
        if store.isPremium {
            destinationRow(index: 1, name: $ssd2Name, folder: $ssd2Folder, label: "SSD 2 (mirror)")
        } else {
            proLockedRow(label: "SSD 2 (mirror)")
        }
    }

    @ViewBuilder
    private var ssd3Row: some View {
        if store.isPremium {
            destinationRow(index: 2, name: $ssd3Name, folder: $ssd3Folder, label: "SD Card (transit)")
        } else {
            proLockedRow(label: "SD Card (transit)")
        }
    }

    @ViewBuilder
    private func proLockedRow(label: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline)
                    Text("Pro feature").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "externaldrive.fill")
            }
            Spacer()
            Button("Unlock") { showPaywall = true }
                .font(.callout)
                .foregroundStyle(Color.accentColor)
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func destinationRow(index: Int, name: Binding<String>, folder: Binding<String>, label: String) -> some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline)
                    if name.wrappedValue.isEmpty {
                        Text("Not configured").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(name.wrappedValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        if !folder.wrappedValue.isEmpty {
                            Text(folder.wrappedValue)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } icon: {
                Image(systemName: "externaldrive.fill")
            }

            Spacer()

            Button("Choose…") {
                if ProcessInfo.processInfo.isiOSAppOnMac {
                    guard let url = MacOpenPanel.pickFolder() else { return }
                    let dm = DestinationManager.shared
                    dm.saveBookmark(url: url, forKey: dm.key(for: index))
                    loadNames()
                    viewModel.refreshDestinationStatuses()
                } else {
                    pickerIndex = index
                    showPicker = true
                }
            }
            .font(.callout)

            if !name.wrappedValue.isEmpty {
                Button(role: .destructive) {
                    DestinationManager.shared.clearBookmark(forKey: DestinationManager.shared.key(for: index))
                    loadNames()
                    viewModel.refreshDestinationStatuses()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var customExtensionsLabel: String {
        let exts = customExtensionsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return exts.isEmpty ? "None" : exts.map { ".\($0)" }.joined(separator: ", ")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private func loadNames() {
        let dm = DestinationManager.shared
        ssd1Name   = dm.displayName(forKey: dm.key(for: 0))
        ssd2Name   = dm.displayName(forKey: dm.key(for: 1))
        ssd3Name   = dm.displayName(forKey: dm.key(for: 2))
        ssd1Folder = dm.folderName(forKey: dm.key(for: 0))
        ssd2Folder = dm.folderName(forKey: dm.key(for: 1))
        ssd3Folder = dm.folderName(forKey: dm.key(for: 2))
    }
}

// MARK: - CustomExtensionsView

struct CustomExtensionsView: View {
    @AppStorage("customExtensions") private var raw: String = ""
    @State private var newExt: String = ""

    private var extensions: [String] {
        raw.split(separator: ",")
           .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
           .filter { !$0.isEmpty }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("e.g. srt, gpx, csv", text: $newExt)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Add") { addExtension() }
                        .disabled(newExt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Add extension")
            } footer: {
                Text("Files with these extensions will be included in every backup, for all device types. Enter without the dot.")
            }

            if !extensions.isEmpty {
                Section("Active") {
                    ForEach(extensions, id: \.self) { ext in
                        Label(".\(ext)", systemImage: "doc.badge.plus")
                            .font(.system(.body, design: .monospaced))
                    }
                    .onDelete { indices in
                        var updated = extensions
                        updated.remove(atOffsets: indices)
                        raw = updated.joined(separator: ",")
                    }
                }
            }
        }
        .navigationTitle("Additional File Types")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addExtension() {
        let ext = newExt
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !ext.isEmpty, !extensions.contains(ext) else { return }
        raw = (extensions + [ext]).joined(separator: ",")
        newExt = ""
    }
}

