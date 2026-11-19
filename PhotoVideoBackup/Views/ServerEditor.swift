import SwiftUI

/// The fields of one server of a backup, whatever its type: the typed connection says which form to show.
/// A type this build does not know is shown as such and left untouched.
struct ServerEditor: View {
    @Binding var connection: ServerConnection
    @Binding var password: String

    var body: some View {
        switch connection {
        case .smb:
            ProfileNASEditor(config: smbBinding, password: $password)
        case .webdav:
            ProfileWebDAVEditor(config: webdavBinding, password: $password)
        case .unknown:
            Section {
                Label("This kind of server needs a newer version of the app.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var smbBinding: Binding<NASConfig> {
        Binding(get: { if case .smb(let c) = connection { return c } else { return .empty } },
                set: { connection = .smb($0) })
    }

    private var webdavBinding: Binding<WebDAVConfig> {
        Binding(get: { if case .webdav(let c) = connection { return c } else { return .empty } },
                set: { connection = .webdav($0) })
    }
}
