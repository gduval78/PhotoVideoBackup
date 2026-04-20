import SwiftUI
import AVKit

// MARK: - BackupBrowserView

struct BackupBrowserView: View {
    @Environment(BackupBrowserViewModel.self) private var browser

    var body: some View {
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
                                        DateListView(deviceFolder: folder)
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
        .onAppear  { browser.startAccess() }
        .onDisappear { browser.stopAccess() }
    }
}

// MARK: - DateListView

private struct DateListView: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    let deviceFolder: URL

    var body: some View {
        let dates = browser.dateFolders(in: deviceFolder)
        Group {
            if dates.isEmpty {
                emptyState(icon: "calendar.badge.exclamationmark", title: "No dates found", message: nil)
            } else {
                List(dates, id: \.self) { dateFolder in
                    NavigationLink {
                        MediaGridView(dateFolder: dateFolder)
                    } label: {
                        Label(dateFolder.lastPathComponent, systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle(deviceFolder.lastPathComponent)
    }
}

// MARK: - MediaGridView

private struct MediaGridView: View {
    @Environment(BackupBrowserViewModel.self) private var browser
    let dateFolder: URL

    @State private var selectionMode = false
    @State private var selectedURLs: Set<URL> = []
    @State private var shareItems: [URL] = []
    @State private var showShareSheet = false
    @State private var isPreparing = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        let files = browser.mediaFiles(in: dateFolder)
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
                            } else {
                                NavigationLink {
                                    MediaDetailView(url: file, isVideo: browser.isVideo(file))
                                } label: {
                                    ThumbnailCell(url: file, isVideo: browser.isVideo(file))
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
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(dateFolder.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFiles) {
            ActivityShareSheet(items: shareItems)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { cancelSelection() }
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

    private func toggleSelection(_ url: URL) {
        if selectedURLs.contains(url) { selectedURLs.remove(url) }
        else { selectedURLs.insert(url) }
    }

    private func cancelSelection() {
        selectionMode = false
        selectedURLs = []
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

        shareItems = copied
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
    var isSelected: Bool = false
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

// MARK: - ActivityShareSheet

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
                    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
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
