import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - BackupBrowserView

struct BackupBrowserView: View {
    @Environment(BackupBrowserViewModel.self) private var browser

    var body: some View {
        let _ = browser.folderListVersion
        Group {
            if browser.destinations.isEmpty {
                emptyState(
                    icon: "externaldrive.badge.xmark",
                    title: "No SSD Connected",
                    message: "Connect your SSD and configure a destination in Settings."
                )
            } else {
                List {
                    ForEach(browser.destinations) { dest in
                        let folders = browser.deviceFolders(in: dest.url)
                        Section(dest.name) {
                            if folders.isEmpty {
                                Text("No backups yet on this SSD.")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(folders, id: \.self) { folder in
                                    NavigationLink {
                                        DeviceFolderView(folder: folder)
                                    } label: {
                                        Label(folder.lastPathComponent, systemImage: "folder.fill")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Browse Backup")
    }
}

// MARK: - DeviceFolderView

private struct DeviceFolderView: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    let folder: URL

    @State private var activeLUT: ParsedLUT?
    @State private var showLUTPicker = false

    var body: some View {
        let _ = browser.folderListVersion
        let subfolders = browser.dateFolders(in: folder)
        let files      = browser.mediaFiles(in: folder)
        let isGrading  = browser.gradingDeviceFolder == folder

        Group {
            if subfolders.isEmpty && files.isEmpty {
                emptyState(icon: "folder.badge.questionmark", title: "Empty folder", message: nil)
            } else {
                List {
                    if !folder.lastPathComponent.hasSuffix(" (Graded)") {
                        lutSection(isGrading: isGrading)
                    }

                    if !subfolders.isEmpty {
                        Section {
                            ForEach(subfolders, id: \.self) { sub in
                                NavigationLink {
                                    FolderContentView(folder: sub, activeLUT: activeLUT, deviceFolder: folder)
                                } label: {
                                    Label(sub.lastPathComponent, systemImage: "folder.fill")
                                }
                            }
                        }
                    }

                    if !files.isEmpty {
                        Section {
                            NavigationLink {
                                MediaGridView(folder: folder, activeLUT: activeLUT, deviceFolder: folder)
                            } label: {
                                Label(
                                    "\(files.count) \(files.count == 1 ? "file" : "files") in this folder",
                                    systemImage: "photo.stack"
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.lastPathComponent)
        .sheet(isPresented: $showLUTPicker, onDismiss: loadAssignedLUT) {
            LUTPickerSheet(deviceFolder: folder)
                .environment(browser)
        }
        .onAppear { loadAssignedLUT() }
    }

    @ViewBuilder
    private func lutSection(isGrading: Bool) -> some View {
        Section("LUT Grade") {
            if let lut = activeLUT {
                HStack {
                    Label(lut.name, systemImage: "camera.filters")
                    Spacer()
                    Button("Remove") {
                        browser.removeLUT(from: folder)
                        activeLUT = nil
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                }

                if isGrading, let state = browser.gradingState {
                    if state.isFinished {
                        Label("Grading complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(state.completed),
                                         total: max(Double(state.total), 1))
                            HStack {
                                Text("\(state.completed)/\(state.total) — \(state.currentFile)")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Button("Cancel") { browser.cancelGrading() }
                                    .font(.caption).foregroundStyle(.red).buttonStyle(.borderless)
                            }
                        }
                    }
                } else {
                    Text("Select videos in the grid, then tap Grade.")
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

    private func loadAssignedLUT() {
        guard let lutName = browser.assignedLUTName(for: folder),
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
}

// MARK: - FolderContentView

private struct FolderContentView: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    let folder: URL
    let activeLUT: ParsedLUT?
    let deviceFolder: URL

    var body: some View {
        let subfolders = browser.dateFolders(in: folder)
        let files      = browser.mediaFiles(in: folder)

        Group {
            if subfolders.isEmpty && files.isEmpty {
                emptyState(icon: "folder.badge.questionmark", title: "Empty folder", message: nil)
            } else if subfolders.isEmpty {
                MediaGridView(folder: folder, activeLUT: activeLUT, deviceFolder: deviceFolder)
            } else {
                List {
                    Section {
                        ForEach(subfolders, id: \.self) { sub in
                            NavigationLink {
                                FolderContentView(folder: sub, activeLUT: activeLUT, deviceFolder: deviceFolder)
                            } label: {
                                Label(sub.lastPathComponent, systemImage: "folder.fill")
                            }
                        }
                    }
                    if !files.isEmpty {
                        Section {
                            NavigationLink {
                                MediaGridView(folder: folder, activeLUT: activeLUT, deviceFolder: deviceFolder)
                            } label: {
                                Label(
                                    "\(files.count) \(files.count == 1 ? "file" : "files") in this folder",
                                    systemImage: "photo.stack"
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.lastPathComponent)
    }
}

// MARK: - MediaGridView

private struct MediaGridView: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    @Environment(StoreManager.self) private var store
    let folder: URL
    let activeLUT: ParsedLUT?
    let deviceFolder: URL

    @State private var selectionMode   = false
    @State private var selectedURLs: Set<URL> = []
    @State private var shareItems: [URL] = []
    @State private var showShareSheet  = false
    @State private var isPreparing     = false
    @State private var playingVideoURL: URL?
    @State private var showPaywall     = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    private var gradableSelected: [URL] {
        selectedURLs.filter {
            BackupBrowserViewModel.gradableExtensions.contains($0.pathExtension.lowercased())
        }
    }

    var body: some View {
        let files = browser.mediaFiles(in: folder)
        Group {
            if files.isEmpty {
                emptyState(icon: "photo.slash", title: "No media files", message: nil)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(files, id: \.self) { file in
                            if selectionMode {
                                ThumbnailCell(
                                    url: file,
                                    isVideo: browser.isVideo(file),
                                    selectionMode: true,
                                    isSelected: selectedURLs.contains(file)
                                )
                                .onTapGesture { toggleSelection(file) }
                            } else if browser.isVideo(file) {
                                Button { playingVideoURL = file } label: {
                                    ThumbnailCell(url: file, isVideo: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    MediaDetailView(url: file, isVideo: false)
                                } label: {
                                    ThumbnailCell(url: file, isVideo: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .overlay {
                    if isPreparing {
                        ZStack {
                            Color.black.opacity(0.4).ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView().tint(.white)
                                Text("Preparing \(selectedURLs.count) file(s)…")
                                    .foregroundStyle(.white).font(.subheadline)
                            }
                        }
                    } else if browser.gradingDeviceFolder == deviceFolder,
                              let state = browser.gradingState, !state.isFinished {
                        ZStack {
                            Color.black.opacity(0.5).ignoresSafeArea()
                            VStack(spacing: 12) {
                                ProgressView(value: Double(state.completed),
                                             total: max(Double(state.total), 1))
                                    .tint(.white).padding(.horizontal, 40)
                                Text("Grading \(state.completed) / \(state.total)")
                                    .foregroundStyle(.white).font(.subheadline)
                                Text(state.currentFile)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .font(.caption).lineLimit(1)
                                Button("Cancel") { browser.cancelGrading() }
                                    .foregroundStyle(.white).buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ActivityShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { playingVideoURL != nil },
            set: { if !$0 { playingVideoURL = nil } }
        )) {
            if let url = playingVideoURL {
                VideoFullScreenView(url: url, activeLUT: activeLUT)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { cancelSelection() }
            }
            if activeLUT != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { startGradingSelected() } label: {
                        Label("Grade", systemImage: "camera.filters")
                    }
                    .disabled(gradableSelected.isEmpty || browser.gradingState?.isFinished == false)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await prepareAndShare() }
                } label: {
                    Label(
                        selectedURLs.isEmpty ? "Share" : "Share (\(selectedURLs.count))",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(selectedURLs.isEmpty || isPreparing)
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Select") { selectionMode = true }
            }
        }
    }

    private func startGradingSelected() {
        guard store.isPremium else { showPaywall = true; return }
        guard let lut = activeLUT else { return }
        browser.startGrading(files: gradableSelected, lut: lut, deviceFolder: deviceFolder)
        cancelSelection()
    }

    private func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) { selectedURLs.remove(url) }
        else { selectedURLs.insert(url) }
    }

    private func cancelSelection() {
        selectionMode = false
        selectedURLs  = []
    }

    private func prepareAndShare() async {
        isPreparing = true
        let urlsToShare = Array(selectedURLs)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pvb_share_\(UUID().uuidString)", isDirectory: true)

        let copied: [URL] = await Task.detached(priority: .userInitiated) {
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            return urlsToShare.compactMap { source in
                let dest = tmpDir.appendingPathComponent(source.lastPathComponent)
                try? FileManager.default.copyItem(at: source, to: dest)
                return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
            }
        }.value

        shareItems  = copied
        isPreparing = false
        if !copied.isEmpty { showShareSheet = true }
    }

    private func cleanupTempFiles() {
        let toDelete = shareItems.first.map { $0.deletingLastPathComponent() }
        Task.detached { if let dir = toDelete { try? FileManager.default.removeItem(at: dir) } }
        shareItems = []
        cancelSelection()
    }
}

// MARK: - ThumbnailCell

private struct ThumbnailCell: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    let url: URL
    let isVideo: Bool
    var selectionMode: Bool = false
    var isSelected: Bool    = false
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: isVideo ? "video" : "photo")
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: 110, height: 110)
            .clipped()
            .opacity(selectionMode && !isSelected ? 0.55 : 1.0)

            if isVideo && !selectionMode {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .white)
                    .shadow(radius: 1)
                    .padding(5)
            }
        }
        .task(id: url) {
            thumbnail = await browser.thumbnail(for: url)
        }
    }
}

// MARK: - LUTPickerSheet

private struct LUTPickerSheet: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    @Environment(\.dismiss) private var dismiss
    let deviceFolder: URL

    @State private var lutStore        = LUTStore.shared
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                lutListSection
                importSection
            }
            .navigationTitle("Select LUT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
            .alert("Import Failed", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    @ViewBuilder
    private var lutListSection: some View {
        Section("Available LUTs") {
            if lutStore.files.isEmpty {
                Text("No LUTs imported yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lutStore.files) { lut in
                    lutRow(lut)
                }
            }
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            Button { showFileImporter = true } label: {
                Label("Import LUT (.cube)…", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    private func lutRow(_ lut: LUTFile) -> some View {
        let isSelected = browser.assignedLUTName(for: deviceFolder) == lut.url.lastPathComponent
        HStack {
            Label(lut.name, systemImage: "camera.filters")
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            browser.assignLUT(named: lut.url.lastPathComponent, to: deviceFolder)
            dismiss()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if isSelected { browser.removeLUT(from: deviceFolder) }
                lutStore.delete(lut)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            try lutStore.importLUT(from: url)
            if let imported = lutStore.files.first(where: {
                $0.url.lastPathComponent == url.lastPathComponent
            }) {
                browser.assignLUT(named: imported.url.lastPathComponent, to: deviceFolder)
                dismiss()
            }
        } catch {
            importError = error.localizedDescription
        }
    }

}

// MARK: - ActivityShareSheet

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - VideoFullScreenView

private struct VideoFullScreenView: View {
    let url: URL
    let activeLUT: ParsedLUT?

    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var playerAsset: AVURLAsset?
    @State private var lutEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                AVPlayerViewControllerRepresentable(player: player)
                    .ignoresSafeArea()
            }
            VStack {
                // Dismiss — top right (does not overlap AVPlayerViewController native controls)
                HStack {
                    Spacer()
                    Button { player?.pause(); dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.55))
                            .padding()
                    }
                }
                Spacer()
                // LUT toggle — bottom left, well clear of the native scrubber bar
                if activeLUT != nil {
                    HStack {
                        Button { Task { await toggleLUT() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.filters")
                                    .symbolVariant(lutEnabled ? .fill : .none)
                                Text(lutEnabled ? "LUT ON" : "LUT")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(lutEnabled ? Color.black : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(
                                lutEnabled ? Color.yellow : Color.black.opacity(0.55)
                            ))
                        }
                        .padding(.leading)
                        .padding(.bottom, 80)  // clear native scrubber area
                        Spacer()
                    }
                }
            }
        }
        .task {
            let a    = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: a)
            let p    = AVPlayer(playerItem: item)
            playerAsset = a
            playerItem  = item
            player      = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }

    private func toggleLUT() async {
        guard let lut = activeLUT,
              let item = playerItem,
              let asset = playerAsset else { return }
        lutEnabled.toggle()
        if lutEnabled {
            try? await asset.load(.tracks)
            let composition = AVMutableVideoComposition(asset: asset) { [lut] request in
                let output = lut.apply(to: request.sourceImage.clampedToExtent()) ?? request.sourceImage
                request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
            }
            item.videoComposition = composition
        } else {
            item.videoComposition = nil
        }
    }
}

// MARK: - AVPlayerViewControllerRepresentable

private struct AVPlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls         = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds   = false
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

// MARK: - MediaDetailView

struct MediaDetailView: View {
    let url: URL
    let isVideo: Bool
    @State private var player: AVPlayer?
    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .horizontal)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                }
            } else {
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                }
            }
        }
        .navigationTitle(url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if isVideo {
                player = AVPlayer(url: url)
                player?.play()
            } else {
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
                loadedImage = await Task.detached(priority: .userInitiated) {
                    let opts: [CFString: Any] = [
                        kCGImageSourceThumbnailMaxPixelSize: 2048,
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
                    else { return nil }
                    return UIImage(cgImage: cg)
                }.value
            }
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - Shared empty state helper

private func emptyState(icon: String, title: String, message: String?) -> some View {
    VStack(spacing: 12) {
        Image(systemName: icon)
            .font(.largeTitle)
            .foregroundStyle(.secondary)
        Text(title)
            .font(.headline)
        if let message {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
