import SwiftUI

/// Shown when the user taps *Run* on a backup card: a picture of what is about to happen — the
/// source and every destination, each with a pictogram of its device — so the user can confirm
/// the operation at a glance (in particular when the destination is a folder on the device itself).
struct BackupSummarySheet: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    let profile: BackupProfile
    let sourceName: String
    let destinationNames: [String]
    let onStart: () -> Void

    /// One box of the diagram.
    struct Node: Identifiable {
        let id = UUID()
        let symbol: String
        let kind: LocalizedStringKey
        let name: String
        var warning: Bool = false
    }

    private var deviceSymbol: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    private var source: Node {
        switch profile.source {
        case .photos:
            return Node(symbol: deviceSymbol, kind: "This device", name: sourceName)
        case .external(let id):
            let type = viewModel.externalSources.first { $0.id == id }?.deviceType ?? .generic
            let symbol: String
            switch type {
            case .djiMini3Pro: symbol = "airplane"
            case .gopro, .insta360X5, .dji360: symbol = "camera.fill"
            case .generic: symbol = "sdcard.fill"
            }
            return Node(symbol: symbol, kind: "Source", name: sourceName)
        }
    }

    private var destinations: [Node] {
        var nodes: [Node] = []
        let dm = DestinationManager.shared
        for (i, key) in profile.folderKeys.enumerated() {
            let name = i < destinationNames.count ? destinationNames[i] : dm.folderName(forKey: key)
            guard let url = dm.resolveBookmark(forKey: key) else {
                nodes.append(Node(symbol: "externaldrive.fill", kind: "External drive", name: name))
                continue
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if ICloudEvictionManager.isUbiquitous(url) {
                nodes.append(Node(symbol: "icloud.fill", kind: "iCloud Drive", name: name))
            } else if Self.isOnDeviceVolume(url) {
                nodes.append(Node(symbol: deviceSymbol, kind: "On this device", name: name, warning: true))
            } else {
                nodes.append(Node(symbol: "externaldrive.fill", kind: "External drive", name: name))
            }
        }
        // Names come in this order: the folders, then the servers.
        for (i, server) in profile.servers.enumerated() {
            let index = profile.folderKeys.count + i
            let name = destinationNames.indices.contains(index) ? destinationNames[index] : server.connection.label
            nodes.append(Node(symbol: server.connection.symbol, kind: "Server", name: name))
        }
        return nodes
    }

    /// The power source, shown only when the backup requires power ("Only run on power"). Orange
    /// while the phone is not charging — the backup would refuse to start.
    private var powerNode: Node? {
        guard profile.settings?.requirePower == true else { return nil }
        let ok = PowerRequirement.isSatisfiedNow(required: true)
        return Node(symbol: "battery.100.bolt", kind: "Power", name: String(localized: "Power bank or charger"), warning: !ok)
    }

    /// True when the folder lives on the same volume as the app, i.e. on the device itself.
    static func isOnDeviceVolume(_ url: URL) -> Bool {
        guard let deviceID = try? FileManager.default.temporaryDirectory
                .resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let targetID = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        else { return false }
        return deviceID.isEqual(targetID)
    }

    var body: some View {
        let dests = destinations
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(verbatim: profile.name).font(.headline).foregroundStyle(.secondary)
                    box(source)
                    Image(systemName: "arrow.down")
                        .font(.title2.weight(.semibold)).foregroundStyle(.tint)
                    ForEach(dests) { node in box(node) }
                    if let power = powerNode {
                        Image(systemName: "bolt.fill").font(.title3).foregroundStyle(.yellow)
                        box(power)
                        if power.warning {
                            Label("The phone is not charging yet: connect the power source or the backup will not start.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    if dests.contains(where: { $0.warning }) {
                        Label("This destination is on the device itself, not on an external drive.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Ready to back up?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    onStart()
                } label: {
                    Text("Start backup").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.regularMaterial)
            }
        }
        .presentationDetents([.large])
    }

    private func box(_ node: Node) -> some View {
        VStack(spacing: 6) {
            Image(systemName: node.symbol)
                .font(.system(size: 40))
                .foregroundStyle(node.warning ? Color.orange : Color.accentColor)
            Text(node.kind).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: node.name).font(.headline).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(node.warning ? Color.orange.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
    }
}
