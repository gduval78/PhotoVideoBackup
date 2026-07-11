import SwiftUI

// MARK: - RenameSheet

struct RenameSheet: View {
    let files: [URL]
    let folder: URL
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pattern     = RenamePattern(raw: "{original}", indexWidth: 3)
    @State private var captureDates: [URL: Date?] = [:]
    @State private var isRenaming  = false
    @State private var progress    = 0
    @State private var errorMessage: String?

    private var sortedFiles: [URL] {
        files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private var previewFiles: [URL] {
        Array(sortedFiles.prefix(3))
    }

    var body: some View {
        NavigationStack {
            Form {
                patternSection
                indexWidthSection
                previewSection
                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Rename \(files.count) File(s)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isRenaming)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isRenaming {
                        Text(verbatim: "\(progress) / \(files.count)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Button("Rename") {
                            Task { await performRename() }
                        }
                        .disabled(pattern.raw.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .task {
                await loadCaptureDates()
            }
        }
    }

    // MARK: - Sections

    private var patternSection: some View {
        Section {
            TextField("Pattern", text: $pattern.raw)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.body, design: .monospaced))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RenamePattern.tokens, id: \.token) { item in
                        Button {
                            pattern.raw += item.token
                        } label: {
                            Text(item.token)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Pattern")
        } footer: {
            Text("Tap a token to insert it. Anything else is literal text.")
        }
    }

    private var indexWidthSection: some View {
        Section("Index width") {
            Picker("Digits", selection: $pattern.indexWidth) {
                Text("2 — 01").tag(2)
                Text("3 — 001").tag(3)
                Text("4 — 0001").tag(4)
            }
            .pickerStyle(.segmented)
        }
    }

    private var previewSection: some View {
        Section("Preview (first \(previewFiles.count))") {
            if captureDates.isEmpty && !previewFiles.isEmpty {
                ProgressView("Reading metadata…")
            } else {
                ForEach(Array(previewFiles.enumerated()), id: \.offset) { idx, url in
                    let date    = captureDates[url] ?? nil
                    let newName = pattern.filename(
                        original: url.lastPathComponent, captureDate: date, index: idx)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: url.lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: "→ \(newName)")
                            .font(.caption).foregroundStyle(.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadCaptureDates() async {
        let urls = sortedFiles
        var result: [URL: Date?] = [:]
        await withTaskGroup(of: (URL, Date?).self) { group in
            for url in urls {
                group.addTask {
                    let d = await Task.detached { RenamePattern.captureDate(at: url) }.value
                    // Fall back to IndexStore captureDate if EXIF unavailable
                    if d == nil {
                        let stored = await MainActor.run {
                            IndexStore.shared.captureDate(forDestinationPath: url.path)
                        }
                        return (url, stored)
                    }
                    return (url, d)
                }
            }
            for await pair in group { result[pair.0] = pair.1 }
        }
        captureDates = result
    }

    private func performRename() async {
        isRenaming  = true
        errorMessage = nil
        progress    = 0

        let ordered = sortedFiles
        var failed: [String] = []

        for (index, url) in ordered.enumerated() {
            let date    = captureDates[url] ?? nil
            var newName = pattern.filename(
                original: url.lastPathComponent, captureDate: date, index: index)

            // Resolve name conflicts within the folder
            newName = resolvedName(newName, in: folder, excluding: url)

            let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: url, to: dest)
                await MainActor.run {
                    IndexStore.shared.updateDestinationPath(from: url.path, to: dest.path)
                }
            } catch {
                failed.append(url.lastPathComponent)
            }

            progress = index + 1
        }

        isRenaming = false

        if failed.isEmpty {
            onComplete()
            dismiss()
        } else {
            errorMessage = String(format: String(localized: "%lld file(s) could not be renamed."), failed.count)
        }
    }

    private func resolvedName(_ name: String, in folder: URL, excluding original: URL) -> String {
        let candidate = folder.appendingPathComponent(name)
        guard candidate.path != original.path,
              FileManager.default.fileExists(atPath: candidate.path)
        else { return name }

        let ns  = name as NSString
        let ext  = ns.pathExtension
        let stem = ns.deletingPathExtension
        var i = 2
        while true {
            let alt = stem + "_\(i)" + (ext.isEmpty ? "" : "." + ext)
            let altURL = folder.appendingPathComponent(alt)
            if !FileManager.default.fileExists(atPath: altURL.path) { return alt }
            i += 1
        }
    }
}
