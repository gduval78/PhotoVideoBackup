import SwiftUI

/// The fields of a NAS (SMB) destination, bound to a profile's own NAS config and password. Used by
/// the "New backup" flow and by a backup's settings — each backup can point at a different NAS.
struct ProfileNASEditor: View {
    @Binding var config: NASConfig
    @Binding var password: String

    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    /// The port is edited as text and parsed digits-only (never a locale-formatted numeric field).
    private var portText: Binding<String> {
        Binding(get: { String(config.port) },
                set: { config.port = Int($0.filter(\.isNumber)) ?? 445 })
    }

    var body: some View {
        Section("Server") {
            field("Name", "e.g. Synology NAS", $config.displayName)
            field("Host / IP", "192.168.1.20", $config.host, keyboard: .URL)
            field("Port", "445", portText, keyboard: .numberPad)
            field("Share", "e.g. photo", $config.share)
            field("Folder", "optional, e.g. Backups", $config.basePath)
        }
        Section("Credentials") {
            field("Username", "", $config.username)
            HStack {
                Text("Password").frame(width: 90, alignment: .leading)
                SecureField("Password", text: $password)
            }
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
            .disabled(isTesting)
            if let testMessage {
                Text(verbatim: testMessage).font(.caption).foregroundStyle(testSucceeded ? .green : .red)
            }
        }
    }

    private func test() async {
        isTesting = true
        testMessage = nil
        let cleaned = trimmed(config)
        let result = await DestinationManager.shared.testNASConnection(cleaned, password: password)
        testSucceeded = result.success
        testMessage = result.message
        isTesting = false
    }

    private func trimmed(_ c: NASConfig) -> NASConfig {
        var t = c
        t.host = c.host.trimmingCharacters(in: .whitespaces)
        t.share = c.share.trimmingCharacters(in: .whitespaces)
        t.basePath = c.basePath.trimmingCharacters(in: .whitespaces)
        t.username = c.username.trimmingCharacters(in: .whitespaces)
        t.displayName = c.displayName.trimmingCharacters(in: .whitespaces)
        return t
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
