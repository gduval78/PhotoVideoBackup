import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @Environment(LanguageManager.self)    private var languageManager
    @State private var ssd1Name:   String = ""
    @State private var ssd2Name:   String = ""
    @State private var ssd1Folder: String = ""
    @State private var ssd2Folder: String = ""
    @State private var nasLabel:   String = ""   // empty = NAS not configured
    @State private var showPicker: Bool = false
    @State private var pickerIndex: Int = 0
    @State private var showPaywall: Bool = false
    @FocusState private var limitFieldFocused: Bool
    @State private var limitText: String = ""   // editing buffer, decoupled from @AppStorage
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
                        Text(mode.labelKey).tag(mode.rawValue)
                    }
                }
                HStack {
                    Text("Max files per session")
                    Spacer()
                    TextField("Unlimited", text: $limitText)
                        .keyboardType(.numberPad)
                        .focused($limitFieldFocused)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                        .onChange(of: limitFieldFocused) { _, focused in
                            if !focused { commitLimit() }
                        }
                }
                NavigationLink {
                    CustomExtensionsView()
                } label: {
                    HStack {
                        Text("Additional file types")
                        Spacer()
                        if customExtensionsRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("None")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Text(customExtensionsLabel)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section("Language") {
                @Bindable var lm = languageManager
                Picker("Language", selection: $lm.selectedCode) {
                    Text("System Default").tag("")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Italiano").tag("it")
                    Text("Português").tag("pt")
                    Text("中文").tag("zh-Hans")
                    Text("Русский").tag("ru")
                }
            }

            Section("Destinations") {
                destinationRow(index: 0, name: $ssd1Name, folder: $ssd1Folder, label: "SSD 1 (primary)")
                ssd2Row
                nasRow
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

            Section("Support") {
                Link(destination: URL(string: AppConstants.documentationURL)!) {
                    Label("Documentation", systemImage: "book")
                }
                HStack {
                    Image(systemName: "envelope")
                        .foregroundStyle(.secondary)
                    Text(verbatim: AppConstants.supportEmail)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Button {
                    if let url = AppConstants.supportMailtoURL() {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Contact Support", systemImage: "envelope.badge")
                }
            }

        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { limitFieldFocused = false }
            }
        }
        .onAppear { loadNames() }
        .onDisappear { commitLimit() }
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

    // MARK: - SSD 2 / NAS rows (Pro only)

    @ViewBuilder
    private var ssd2Row: some View {
        if store.isPremium {
            destinationRow(index: 1, name: $ssd2Name, folder: $ssd2Folder, label: "SSD 2 (mirror)")
        } else {
            proLockedRow(label: "SSD 2 (mirror)")
        }
    }

    @ViewBuilder
    private var nasRow: some View {
        if store.isPremium {
            NavigationLink {
                NASSettingsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NAS (SMB)").font(.subheadline)
                        if nasLabel.isEmpty {
                            Text("Not configured").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: nasLabel)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                } icon: {
                    Image(systemName: "externaldrive.connected.to.line.below")
                }
            }
        } else {
            proLockedRow(label: "NAS (SMB)")
        }
    }

    @ViewBuilder
    private func proLockedRow(label: LocalizedStringKey) -> some View {
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
    private func destinationRow(index: Int, name: Binding<String>, folder: Binding<String>, label: LocalizedStringKey) -> some View {
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
        customExtensionsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { ".\($0)" }
            .joined(separator: ", ")
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
        ssd1Folder = dm.folderName(forKey: dm.key(for: 0))
        ssd2Folder = dm.folderName(forKey: dm.key(for: 1))
        if let cfg = dm.loadNASConfig(), cfg.isComplete {
            nasLabel = cfg.label
        } else {
            nasLabel = ""
        }
        // Mirror the stored limit into the editing buffer. 0 = unlimited → empty field so the
        // "Unlimited" placeholder shows (a plain Int would render "0" and hide the placeholder).
        limitText = backupFileLimit > 0 ? String(backupFileLimit) : ""
    }

    /// Parses the editing buffer and writes the stored limit. Uses a locale-independent digit
    /// parse (never the `.number` FormatStyle, which reads the environment locale and could be
    /// re-parsed into a spurious value when the system/app language changes). Empty, zero, or
    /// non-numeric input all mean "unlimited" (0). Re-normalises the buffer so the field and the
    /// stored value can never drift apart.
    private func commitLimit() {
        let value = Self.normalizedFileLimit(from: limitText)
        backupFileLimit = value
        limitText = value > 0 ? String(value) : ""
    }

    /// Pure, locale-independent normaliser for the "Max files per session" field.
    /// Keeps only digits, so grouping separators or stray characters can never corrupt the value;
    /// returns 0 (unlimited) for empty / zero / non-numeric input. Unit-tested by `FileLimitFieldTests`.
    static func normalizedFileLimit(from text: String) -> Int {
        let digits = text.filter(\.isNumber)
        return Int(digits) ?? 0
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
        .toolbar { EditButton() }
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

