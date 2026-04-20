import SwiftUI
import UniformTypeIdentifiers

// MARK: - FolderPickerView

struct FolderPickerView: UIViewControllerRepresentable {
    let initialDirectory: URL?
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.directoryURL = initialDirectory
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(StoreManager.self)       private var store
    @State private var ssd1Name:   String = ""
    @State private var ssd2Name:   String = ""
    @State private var ssd1Folder: String = ""
    @State private var ssd2Folder: String = ""
    @State private var showPickerForIndex: Int? = nil
    @State private var showPaywall: Bool = false
    @AppStorage("deviceName") private var deviceName: String = ""

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

            Section("SSD Destinations") {
                destinationRow(index: 0, name: $ssd1Name, folder: $ssd1Folder, label: "SSD 1 (primary)")
                ssd2Row
            }

            Section {
                Text("Connect your USB-C SSD, then tap Choose… to select the destination folder. You can create a new folder directly in the Files picker before selecting it. Access is preserved across launches via secure bookmarks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear { loadNames() }
        .sheet(item: $showPickerForIndex) { index in
            let dm = DestinationManager.shared
            let initialDir = dm.resolveBookmark(forKey: dm.key(for: index))
                               .map { $0.deletingLastPathComponent() }
            FolderPickerView(initialDirectory: initialDir) { url in
                showPickerForIndex = nil
                dm.saveBookmark(url: url, forKey: dm.key(for: index))
                loadNames()
                viewModel.refreshDestinationStatuses()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - SSD 2 row (Pro only)

    @ViewBuilder
    private var ssd2Row: some View {
        if store.isPremium {
            destinationRow(index: 1, name: $ssd2Name, folder: $ssd2Folder, label: "SSD 2 (mirror)")
        } else {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SSD 2 (mirror)").font(.subheadline)
                        Text("Pro feature").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "externaldrive.fill")
                }

                Spacer()

                Button("Unlock") {
                    showPaywall = true
                }
                .font(.callout)
                .foregroundStyle(Color.accentColor)

                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
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
                showPickerForIndex = index
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

    private func loadNames() {
        let dm = DestinationManager.shared
        ssd1Name   = dm.displayName(forKey: dm.key(for: 0))
        ssd2Name   = dm.displayName(forKey: dm.key(for: 1))
        ssd1Folder = dm.folderName(forKey: dm.key(for: 0))
        ssd2Folder = dm.folderName(forKey: dm.key(for: 1))
    }
}

// Make Int? conform to Identifiable for .sheet(item:)
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
