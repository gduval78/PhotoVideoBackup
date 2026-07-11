import SwiftUI
import QuickLook

// MARK: - NASBrowserRootView

/// Connects to the configured NAS, then shows its share (starting at the configured base folder).
/// Reached from the Browse tab when a NAS is configured.
struct NASBrowserRootView: View {
    let title: String

    @State private var target: SMBTarget?
    @State private var connecting = true
    @State private var connectError: String?

    var body: some View {
        Group {
            if let target {
                NASBrowserView(target: target, subPath: "", title: title)
            } else if connecting {
                ProgressView("Connecting to NAS…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Could not connect to the NAS.").font(.headline)
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
        target = await DestinationManager.shared.makeSMBTarget()
        if target == nil { connectError = String(localized: "The NAS is unreachable — check Wi-Fi/VPN and settings.") }
        connecting = false
    }
}

// MARK: - NASBrowserView

/// Lists one SMB directory (relative to the NAS base folder). Folders push a deeper view;
/// tapping a file downloads it on demand to a temp file and previews it via QuickLook.
struct NASBrowserView: View {
    @Environment(LanguageManager.self) private var languageManager
    @Environment(BackupBrowserViewModel.self) private var browser
    @Environment(StoreManager.self) private var store

    let target: SMBTarget
    let subPath: String
    let title: String

    @State private var entries: [SMBTarget.Entry] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var busyName: String?
    @State private var previewURL: URL?
    @State private var tempURL: URL?
    @State private var activeLUT: ParsedLUT?
    @State private var showLUTPicker = false
    @State private var playingVideoURL: URL?
    @State private var showPaywall = false
    @State private var selectionMode = false
    @State private var selectedNames: Set<String> = []

    /// LUT Grade is offered at folder level (like local device folders), never at the NAS
    /// root (`subPath` empty) nor inside an already-graded folder.
    private var gradeEligible: Bool {
        !subPath.isEmpty && !title.hasSuffix(" (Graded)")
    }

    private var folderKey: String { BackupBrowserViewModel.nasLUTKey(subPath: subPath) }

    private static let videoExts: Set<String> = ["mp4", "mov", "avi", "m4v", "insv", "braw"]
    private func isVideo(_ name: String) -> Bool {
        Self.videoExts.contains((name as NSString).pathExtension.lowercased())
    }

    /// Only `.mp4`/`.mov` files can actually be graded (AVAssetExportSession re-encode).
    private var gradableEntryNames: [String] {
        entries.filter { !$0.isDirectory
            && BackupBrowserViewModel.gradableExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
            .map(\.name)
    }

    var body: some View {
        List {
            if gradeEligible {
                lutGradeSection
            }

            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let loadError {
                Text(verbatim: loadError).font(.caption).foregroundStyle(.red)
            } else if entries.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    if selectionMode {
                        if !entry.isDirectory && isVideo(entry.name) {
                            Button { toggleSelection(entry.name) } label: {
                                HStack {
                                    Image(systemName: selectedNames.contains(entry.name)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedNames.contains(entry.name)
                                                         ? Color.accentColor : .secondary)
                                    row(entry)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Folders and non-gradable files are not selectable in grade mode.
                            row(entry).foregroundStyle(.secondary)
                        }
                    } else if entry.isDirectory {
                        NavigationLink {
                            NASBrowserView(target: target, subPath: child(entry.name), title: entry.name)
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
        .toolbar { gradeToolbar }
        .task { await load() }
        .onAppear { loadAssignedLUT() }
        .onChange(of: browser.folderListVersion) { _, _ in
            // A finished grading run creates a new "(Graded)" sibling — re-list so it appears.
            Task { await load() }
        }
        .sheet(isPresented: $showLUTPicker, onDismiss: loadAssignedLUT) {
            LUTPickerSheet(folderKey: folderKey)
                .environment(browser)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingVideoURL != nil },
            set: { if !$0 { playingVideoURL = nil; cleanupTemp() } }
        )) {
            if let url = playingVideoURL {
                VideoFullScreenView(url: url, activeLUT: activeLUT)
            }
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, newValue in
            if newValue == nil { cleanupTemp() }
        }
    }

    // MARK: LUT Grade section

    @ViewBuilder
    private var lutGradeSection: some View {
        let isGrading = browser.nasGradingSubPath == subPath
        Section("LUT Grade") {
            if let lut = activeLUT {
                HStack {
                    Label(lut.name, systemImage: "camera.filters")
                    Spacer()
                    Button("Remove") {
                        browser.removeLUT(forKey: folderKey)
                        activeLUT = nil
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }

                if isGrading, let state = browser.nasGradingState {
                    if state.isFinished {
                        Label("Grading complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(state.completed),
                                         total: max(Double(state.total), 1))
                            HStack {
                                Text("Grading \(state.completed) / \(state.total)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !state.currentFile.isEmpty {
                                    Text(verbatim: "— \(state.currentFile)")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Cancel") { browser.cancelNASGrading() }
                                    .font(.caption).foregroundStyle(.red).buttonStyle(.borderless)
                            }
                        }
                    }
                } else {
                    Text("Select only your LOG videos to grade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Downloading, grading, and uploading to a “(Graded)” copy on the NAS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button { showLUTPicker = true } label: {
                    Label("Assign LUT…", systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: Grade selection

    @ToolbarContentBuilder
    private var gradeToolbar: some ToolbarContent {
        if gradeEligible, activeLUT != nil {
            if selectionMode {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { exitSelection() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    let vids = gradableEntryNames
                    Button(selectedNames.count == vids.count && !vids.isEmpty ? "Deselect All" : "Select All") {
                        let vids = gradableEntryNames
                        selectedNames = selectedNames.count == vids.count ? [] : Set(vids)
                    }
                    .disabled(gradableEntryNames.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { startGradeSelected() } label: {
                        Label("Grade", systemImage: "camera.filters")
                    }
                    .disabled(selectedNames.isEmpty || browser.nasGradingState?.isFinished == false)
                }
            } else {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select") { selectionMode = true }
                        .disabled(gradableEntryNames.isEmpty)
                }
            }
        }
    }

    private func startGradeSelected() {
        guard store.isPremium else { showPaywall = true; return }
        guard let lut = activeLUT else { return }
        browser.startNASGrading(target: target, subPath: subPath, relFiles: Array(selectedNames), lut: lut)
        exitSelection()
    }

    private func toggleSelection(_ name: String) {
        if selectedNames.contains(name) { selectedNames.remove(name) } else { selectedNames.insert(name) }
    }

    private func exitSelection() {
        selectionMode = false
        selectedNames = []
    }

    private func loadAssignedLUT() {
        guard let lutName = browser.assignedLUTName(forKey: folderKey),
              let lutFile = LUTStore.shared.files.first(where: { $0.url.lastPathComponent == lutName })
        else {
            activeLUT = nil
            return
        }
        let url = lutFile.url
        Task {
            let parsed = await Task.detached(priority: .userInitiated) {
                try? LUTStore.parseCube(at: url)
            }.value
            activeLUT = parsed
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: SMBTarget.Entry) -> some View {
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

    private func subtitle(_ entry: SMBTarget.Entry) -> String {
        var parts = [entry.size.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))]
        if let date = entry.modificationDate {
            parts.append(date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(languageManager.currentLocale)))
        }
        return parts.joined(separator: " · ")
    }

    private func icon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ["mp4", "mov", "avi", "m4v", "insv", "braw"].contains(ext) { return "film" }
        if ["jpg", "jpeg", "png", "heic", "dng", "raw", "cr2", "cr3", "arw", "nef", "rw2"].contains(ext) { return "photo" }
        return "doc"
    }

    // MARK: Actions

    private func child(_ name: String) -> String {
        subPath.isEmpty ? name : "\(subPath)/\(name)"
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            entries = try await target.list(relativeSubPath: subPath)
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func preview(_ entry: SMBTarget.Entry) async {
        busyName = entry.name
        defer { busyName = nil }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_nas_\(UUID().uuidString)")
            .appendingPathComponent(entry.name)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await target.download(relativeSubPath: child(entry.name), to: dest)
            tempURL = dest
            // Videos open in the full-screen player (with live LUT toggle when a LUT is
            // assigned); everything else uses QuickLook.
            if isVideo(entry.name) {
                playingVideoURL = dest
            } else {
                previewURL = dest
            }
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
