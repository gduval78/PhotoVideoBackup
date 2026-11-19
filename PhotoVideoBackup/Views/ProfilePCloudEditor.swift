import SwiftUI

/// A pCloud destination: sign in on pCloud's own page (no password in the app), name it, pick a folder.
/// The OAuth token is kept in the Keychain through the server's `password` slot.
struct ProfilePCloudEditor: View {
    @Binding var config: PCloudConfig
    @Binding var token: String

    @State private var isSigningIn = false
    @State private var isTesting = false
    @State private var message: String?
    @State private var succeeded = false

    private var signedIn: Bool { config.isComplete && !token.isEmpty }

    var body: some View {
        Section {
            if signedIn {
                Label("Signed in to pCloud.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Sign out", role: .destructive) {
                    token = ""
                    config.userID = 0
                    message = nil
                }
            } else {
                Label("Not signed in yet.", systemImage: "person.crop.circle.badge.exclamationmark").foregroundStyle(.secondary)
            }
            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isSigningIn { ProgressView().padding(.trailing, 4) }
                    Text("Sign in with pCloud")
                }
            }
            .disabled(isSigningIn)
        } header: {
            Text("Account")
        } footer: {
            Text("You sign in on pCloud's own page; the app only keeps an access token in the Keychain, never your password. pCloud does not let an app be limited to one folder, so this token reaches your whole pCloud — the app only uses the folder named below. You can revoke it in your pCloud settings.")
        }
        Section {
            HStack {
                Text("Name").frame(width: 90, alignment: .leading)
                TextField("pCloud", text: $config.displayName)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Folder").frame(width: 90, alignment: .leading)
                TextField("optional, e.g. Backups", text: $config.basePath)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("Destination")
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
            .disabled(isTesting || !signedIn)
            if let message {
                Text(verbatim: message).font(.caption).foregroundStyle(succeeded ? .green : .red)
            }
        }
    }

    private func signIn() async {
        isSigningIn = true
        message = nil
        defer { isSigningIn = false }
        do {
            let result = try await PCloudAuth.signIn()
            token = result.token
            config.userID = result.userID
            config.region = result.region
            succeeded = true
            message = String(localized: "Signed in to pCloud.")
        } catch {
            succeeded = false
            if (error as? PCloudAuthError) != .cancelled { message = error.localizedDescription }
            DiagnosticLog.write("[PCLOUD_ERROR] sign-in: \(error)")
        }
    }

    private func test() async {
        isTesting = true
        message = nil
        defer { isTesting = false }
        do {
            try await config.makeTarget(token: token).testConnection()
            succeeded = true
            message = String(localized: "Connected.")
        } catch {
            succeeded = false
            message = error.localizedDescription
            DiagnosticLog.write("[PCLOUD_ERROR] test: \(error)")
        }
    }
}
