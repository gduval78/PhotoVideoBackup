import SwiftUI

/// Configure a NAS (SMB) backup destination. Saved config lives in UserDefaults; the password
/// is stored in the Keychain. Reachable from Settings → Destinations (Pro).
struct NASSettingsView: View {
    @State private var displayName = ""
    @State private var host = ""
    @State private var port = "445"
    @State private var share = ""
    @State private var basePath = ""
    @State private var username = ""
    @State private var password = ""
    @State private var enabled = true

    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    @State private var didLoad = false

    @State private var showSaveAlert = false
    @State private var saveAlertTitle = ""
    @State private var saveAlertMessage = ""

    var body: some View {
        Form {
            Section("Server") {
                labeledField("Name", "e.g. Synology NAS", $displayName)
                labeledField("Host / IP", "192.168.1.20", $host, keyboard: .URL)
                labeledField("Port", "445", $port, keyboard: .numberPad)
                labeledField("Share", "e.g. photo", $share)
                labeledField("Folder", "optional, e.g. Backups", $basePath)
            }

            Section("Credentials") {
                labeledField("Username", "", $username)
                HStack {
                    Text("Password").frame(width: 90, alignment: .leading)
                    SecureField("Password", text: $password)
                }
            }

            Section {
                Toggle("Use this NAS for backups", isOn: $enabled)
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().padding(.trailing, 4) }
                        Text("Test connection")
                    }
                }
                .disabled(isTesting)

                if let testMessage {
                    Text(verbatim: testMessage)
                        .font(.caption)
                        .foregroundStyle(testSucceeded ? .green : .red)
                }
            }

            Section {
                Button("Save") { save() }

                if DestinationManager.shared.isNASConfigured() {
                    Button(role: .destructive) { clear() } label: {
                        Text("Remove NAS")
                    }
                }
            } footer: {
                Text("The NAS is used as an additional backup destination over Wi-Fi. Files are written directly to the share and verified by SHA-256. The password is stored in the Keychain.")
            }
        }
        .navigationTitle("NAS (SMB)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadOnce)
        .alert(saveAlertTitle, isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: saveAlertMessage)
        }
    }

    // MARK: - Actions

    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        guard let cfg = DestinationManager.shared.loadNASConfig() else { return }
        displayName = cfg.displayName
        host = cfg.host
        port = String(cfg.port)
        share = cfg.share
        basePath = cfg.basePath
        username = cfg.username
        enabled = cfg.enabled
        password = DestinationManager.shared.nasPassword() ?? ""
    }

    private func currentConfig() -> NASConfig {
        NASConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 445,
            share: share.trimmingCharacters(in: .whitespaces),
            basePath: basePath.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            enabled: enabled
        )
    }

    private func testConnection() async {
        guard validate() else { return }
        isTesting = true
        testMessage = nil
        let result = await DestinationManager.shared.testNASConnection(currentConfig(), password: password)
        testSucceeded = result.success
        testMessage = result.message
        isTesting = false
    }

    private func save() {
        let cfg = currentConfig()
        guard cfg.isComplete else {
            presentSaveAlert(title: String(localized: "Cannot save"),
                             message: String(localized: "Please fill in Host, Share and Username."))
            return
        }
        DestinationManager.shared.saveNASConfig(cfg, password: password)
        let stored = DestinationManager.shared.isNASConfigured()
        DiagnosticLog.write("[NAS] save host=\(cfg.host) share=\(cfg.share) stored=\(stored)")
        if stored {
            presentSaveAlert(title: String(localized: "Saved"),
                             message: String(localized: "The NAS “\(cfg.label)” was saved as a backup destination."))
        } else {
            presentSaveAlert(title: String(localized: "Save failed"),
                             message: String(localized: "The NAS destination could not be saved. Please try again."))
        }
    }

    private func presentSaveAlert(title: String, message: String) {
        saveAlertTitle = title
        saveAlertMessage = message
        showSaveAlert = true
    }

    /// Returns true when the required fields are filled; otherwise sets an explanatory message.
    private func validate() -> Bool {
        if currentConfig().isComplete { return true }
        testSucceeded = false
        testMessage = String(localized: "Please fill in Host, Share and Username.")
        return false
    }

    private func clear() {
        DestinationManager.shared.clearNAS()
        displayName = ""; host = ""; port = "445"; share = ""; basePath = ""
        username = ""; password = ""; enabled = true
        testMessage = nil
    }

    // MARK: - Field helper

    @ViewBuilder
    private func labeledField(_ title: LocalizedStringKey, _ placeholder: LocalizedStringKey,
                              _ text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}
