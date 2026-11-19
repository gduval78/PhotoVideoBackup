import SwiftUI
import QuickLook

// MARK: - WebDAVBrowserRootView

/// Connects to a backup's WebDAV server, then lists its backup folder. Reached from the Browse tab.
struct WebDAVBrowserRootView: View {
    let title: String
    let config: WebDAVConfig
    let passwordAccount: String

    @State private var target: WebDAVTarget?
    @State private var connecting = true
    @State private var connectError: String?

    var body: some View {
        Group {
            if let target {
                WebDAVBrowserView(target: target, subPath: "", title: title)
            } else if connecting {
                ProgressView("Connecting to the server…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Could not connect to the server.").font(.headline)
                    if let connectError {
                        Text(verbatim: connectError).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Retry") { Task { await connect() } }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await connect() }
    }

    private func connect() async {
        connecting = true
        connectError = nil
        let password = KeychainStore.get(account: passwordAccount) ?? ""
        if let candidate = config.makeTarget(password: password) {
            if await candidate.isReachable() { target = candidate }
            else { connectError = String(localized: "The server is unreachable — check your connection and settings.") }
        } else {
            connectError = String(localized: "Invalid server address.")
        }
        connecting = false
    }
}

// MARK: - WebDAVBrowserView

/// Lists one WebDAV folder (relative to the backup's base folder). Folders push a deeper view; tapping a
/// file downloads it on demand to a temp file and opens it (video player or QuickLook).
/// LUT Grade is not offered on WebDAV yet.
struct WebDAVBrowserView: View {
    @Environment(LanguageManager.self) private var languageManager

    let target: WebDAVTarget
    let subPath: String
    let title: String

    @State private var entries: [WebDAVTarget.Entry] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var busyName: String?
    @State private var previewURL: URL?
    @State private var tempURL: URL?
    @State private var playingVideoURL: URL?

    private static let videoExts: Set<String> = ["mp4", "mov", "avi", "m4v", "insv", "braw"]
    private func isVideo(_ name: String) -> Bool {
        Self.videoExts.contains((name as NSString).pathExtension.lowercased())
    }

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let loadError {
                Text(verbatim: loadError).font(.caption).foregroundStyle(.red)
            } else if entries.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    if entry.isDirectory {
                        NavigationLink {
                            WebDAVBrowserView(target: target, subPath: child(entry.name), title: entry.name)
                        } label: { row(entry) }
                    } else {
                        Button { Task { await preview(entry) } } label: { row(entry) }
                            .disabled(busyName != nil)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: Binding(
            get: { playingVideoURL != nil },
            set: { if !$0 { playingVideoURL = nil; cleanupTemp() } }
        )) {
            if let url = playingVideoURL {
                VideoFullScreenView(url: url, activeLUT: nil)
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, newValue in
            if newValue == nil { cleanupTemp() }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: WebDAVTarget.Entry) -> some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name).lineLimit(1).truncationMode(.middle)
                if !entry.isDirectory {
                    Text(verbatim: subtitle(entry)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busyName == entry.name { ProgressView() }
        }
    }

    private func subtitle(_ entry: WebDAVTarget.Entry) -> String {
        var parts = [entry.size.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))]
        if let date = entry.modificationDate {
            parts.append(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(languageManager.currentLocale)))
        }
        return parts.joined(separator: " · ")
    }

    private func icon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if Self.videoExts.contains(ext) { return "film" }
        if ["jpg", "jpeg", "png", "heic", "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2"].contains(ext) { return "photo" }
        return "doc"
    }

    // MARK: Actions

    private func child(_ name: String) -> String {
        subPath.isEmpty ? name : "\(subPath)/\(name)"
    }

    private func load() async {
        loading = entries.isEmpty
        loadError = nil
        do {
            entries = try await target.list(relativeSubPath: subPath)
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func preview(_ entry: WebDAVTarget.Entry) async {
        busyName = entry.name
        defer { busyName = nil }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_dav_\(UUID().uuidString)")
            .appendingPathComponent(entry.name)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await target.download(relativeSubPath: child(entry.name), to: dest)
            tempURL = dest
            if isVideo(entry.name) { playingVideoURL = dest } else { previewURL = dest }
        } catch {
            loadError = error.localizedDescription
            try? FileManager.default.removeItem(at: dest.deletingLastPathComponent())
        }
    }

    private func cleanupTemp() {
        guard let tempURL else { return }
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
        self.tempURL = nil
    }
}
