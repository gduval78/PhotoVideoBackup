import SwiftUI

/// The fields of a WebDAV destination, bound to a profile's own config and password. Used by the
/// "New backup" flow and by a backup's settings.
struct ProfileWebDAVEditor: View {
    @Binding var config: WebDAVConfig
    @Binding var password: String

    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    /// Fingerprint of an untrusted certificate the server presented, waiting for the user's decision.
    @State private var pendingFingerprint: String?

    var body: some View {
        Group { content }
            .onChange(of: config.serverURL) { _, _ in
                // A certificate trusted for another address means nothing here.
                config.pinnedCertificate = nil
                pendingFingerprint = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        Section {
            field("Name", "e.g. Nextcloud", $config.displayName)
            field("Server", "https://cloud.example.com/remote.php/dav/files/me/", $config.serverURL, keyboard: .URL)
            field("Folder", "optional, e.g. Backups", $config.basePath)
        } header: {
            Text("Server")
        } footer: {
            Text("The address of your WebDAV server. For Nextcloud it looks like https://your-server/remote.php/dav/files/your-name/. Only secure (https) addresses are accepted.")
        }
        Section {
            field("Username", "", $config.username)
            HStack {
                Text("Password").frame(width: 90, alignment: .leading)
                SecureField("Password", text: $password)
            }
        } header: {
            Text("Credentials")
        } footer: {
            Text("With two-factor authentication, create an app password in your server's security settings and use it here.")
        }
        Section {
            Button {
                Task { await test() }
            } label: {
                HStack {
                    if isTesting { ProgressView().padding(.trailing, 4) }
                    Text("Test connection")
                }
            }
            .disabled(isTesting || !config.isComplete)
            if let testMessage {
                Text(verbatim: testMessage).font(.caption).foregroundStyle(testSucceeded ? .green : .red)
            }
        }
        if let pending = pendingFingerprint {
            Section {
                Text(verbatim: WebDAVTrust.displayFingerprint(pending))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("Trust this certificate") {
                    config.pinnedCertificate = pending
                    pendingFingerprint = nil
                    Task { await test() }
                }
            } header: {
                Text("Untrusted certificate")
            } footer: {
                Text("This server uses a certificate iOS does not trust, which is normal for a server you run yourself. Check that this fingerprint is the one your server shows, then trust it. Only this exact certificate will be accepted.")
            }
        } else if let pinned = config.pinnedCertificate {
            Section {
                Text(verbatim: WebDAVTrust.displayFingerprint(pinned))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("Forget this certificate", role: .destructive) {
                    config.pinnedCertificate = nil
                    testMessage = nil
                }
            } header: {
                Text("Trusted certificate")
            }
        }
    }

    private func test() async {
        isTesting = true
        testMessage = nil
        pendingFingerprint = nil
        defer { isTesting = false }
        guard let target = config.makeTarget(password: password) else {
            testSucceeded = false
            testMessage = String(localized: "Invalid server address.")
            return
        }
        do {
            config.chunking = try await target.testConnection()
            testSucceeded = true
            testMessage = config.chunking == true
                ? String(localized: "Connected. Large files are sent in chunks.")
                : String(localized: "Connected.")
        } catch {
            testSucceeded = false
            testMessage = error.localizedDescription
            if let dav = error as? WebDAVError, dav == .untrustedCertificate, let url = config.url {
                pendingFingerprint = await WebDAVTrust.presentedFingerprint(of: url)
            }
            DiagnosticLog.write("[WEBDAV_ERROR] test \(config.url?.host ?? "?"): \(error.localizedDescription)")
        }
    }

    @ViewBuilder
    private func field(_ title: LocalizedStringKey, _ placeholder: LocalizedStringKey,
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
