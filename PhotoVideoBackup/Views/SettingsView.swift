import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @Environment(LanguageManager.self)    private var languageManager
    /// Which text field has the keyboard. One state for every field of this screen, so the keyboard's
    /// Done button can dismiss whichever one is active (it used to track only the file-limit field,
    /// so Done did nothing while editing the folder name).
    private enum Field { case deviceName, fileLimit }
    @FocusState private var focusedField: Field?
    @State private var limitText: String = ""   // editing buffer, decoupled from @AppStorage
    @State private var showPaywall = false
    @AppStorage("deviceName") private var deviceName: String = ""
    @AppStorage("folderOrganization") private var folderOrganizationRaw: String = FolderOrganization.byDate.rawValue
    @AppStorage("backupFileLimit") private var backupFileLimit: Int = 0
    @AppStorage("customExtensions") private var customExtensionsRaw: String = ""
    @AppStorage(NamingProfile.enabledKey) private var namingEnabled: Bool = false

    var body: some View {
        List {
            Section("iPhone / iPad") {
                HStack {
                    Text("Folder name")
                    Spacer()
                    TextField("e.g. Gerard's iPhone", text: $deviceName)
                        .focused($focusedField, equals: .deviceName)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
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
                        .focused($focusedField, equals: .fileLimit)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                        .onChange(of: focusedField) { oldField, newField in
                            // Leaving the file-limit field (Done, or tapping another field) commits it.
                            if oldField == .fileLimit && newField != .fileLimit { commitLimit() }
                        }
                }
                NavigationLink {
                    NamingProfileView()
                } label: {
                    HStack {
                        Text("File naming")
                        Spacer()
                        Text(namingEnabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                            .font(.caption)
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
            } header: {
                Text("Backup")
            } footer: {
                Text("These are the defaults for new backups. Each backup then has its own settings: Backups tab, long press a backup, Settings.")
            }

            Section("Pro") {
                if store.isPremium {
                    Label("Pro unlocked", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button { showPaywall = true } label: {
                        Label("Upgrade to Pro", systemImage: "star.circle.fill")
                    }
                }
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
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
                Button("Done") { focusedField = nil }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear { loadNames() }
        .onDisappear { commitLimit() }
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



// MARK: - NamingProfileView

/// Settings → Backup → File naming. A pattern applied as each file is first written to the
/// destination, so it carries its final name from the start (see `NamingProfile`).
struct NamingProfileView: View {
    @AppStorage(NamingProfile.enabledKey) private var enabled: Bool = false
    @AppStorage(NamingProfile.patternKey) private var pattern: String = NamingProfile.defaultPattern
    @AppStorage("deviceName") private var deviceName: String = ""
    @FocusState private var patternFocused: Bool

    /// Fixed sample so the example is stable: 28 Sep 2026, 11:35:25 local time.
    private var sampleDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 28; c.hour = 11; c.minute = 35; c.second = 25
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    private var exampleName: String {
        NamingProfile.fileName(original: "IMG_0001.dng", captureDate: sampleDate,
                               device: deviceName.isEmpty ? "MyCamera" : deviceName,
                               enabled: true, pattern: pattern)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Rename files during backup", isOn: $enabled)
            } footer: {
                Text("Each file gets its final name as it is first copied, so it is never stored under its camera name and renamed afterwards. Duplicates are then recognised by that name. Turn off to keep the original file names.")
            }

            if enabled {
                Section {
                    TextField("Pattern", text: $pattern)
                        .focused($patternFocused)
                        .submitLabel(.done)
                        .onSubmit { patternFocused = false }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(NamingProfile.tokens, id: \.self) { token in
                                Button {
                                    pattern += token
                                } label: {
                                    Text(verbatim: token)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Pattern")
                } footer: {
                    Text("Tap a token to insert it. Anything else is literal text. {device} is the device folder name without spaces; {original} is the original name without its extension.")
                }

                Section {
                    Text(verbatim: "IMG_0001.dng")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: "→ \(exampleName)")
                        .font(.caption)
                } header: {
                    Text("Example")
                } footer: {
                    Text("A file is never overwritten: if the name is already used by a different file, the new one is saved with a -1, -2… suffix. Include the seconds or {original} so that two shots taken together keep distinct names.")
                }
            }
        }
        .navigationTitle("File naming")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { patternFocused = false }
            }
        }
    }
}
