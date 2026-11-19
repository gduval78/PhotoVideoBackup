import SwiftUI

/// "New backup": choose **what to back up**, then add its destinations — folders and servers — in the
/// same editor used to change a backup later. No templates, no protocol vocabulary up front.
struct NewBackupFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @State private var path: [NewSource] = []
    @State private var showPaywall = false
    /// Fixed for the whole flow: a folder bookmark is saved under this id's key as soon as it is picked.
    @State private var draftID = UUID()

    /// What the new backup copies from.
    enum NewSource: Hashable {
        case photoLibrary
        case cameraCard

        var requiresPro: Bool { self == .cameraCard }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    row(.photoLibrary, symbol: "photo.on.rectangle.angled",
                        title: "Photo library", detail: "The photos and videos of this iPhone.")
                    row(.cameraCard, symbol: "sdcard.fill",
                        title: "Camera or SD card", detail: "A camera memory card or a USB drive.")
                } footer: {
                    Text("Choose what to back up. You add its destinations next: folders, and servers such as a NAS or Nextcloud.")
                }
            }
            .navigationTitle("New backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(for: NewSource.self) { source in
                ProfileDetailView(profile: draft(for: source), isNew: true) { dismiss() }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private func draft(for source: NewSource) -> BackupProfile {
        BackupProfile(id: draftID, name: "", template: .custom,
                      source: source == .cameraCard ? .external(UUID()) : .photos,
                      destinations: [], settings: ProfileSettings.fromGlobal())
    }

    private func row(_ source: NewSource, symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Button {
            if source.requiresPro && !store.isPremium { showPaywall = true } else { path.append(source) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3).foregroundStyle(Color.accentColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if source.requiresPro && !store.isPremium {
                    Text("Pro").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }
}
