import SwiftUI

struct ReportView: View {
    let session: BackupSession

    var body: some View {
        List {
            headerSection
            summarySection
            filesSection
        }
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = reportHTMLURL {
                    ShareLink(item: url, preview: SharePreview("Backup Report"))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack {
                statusBadge
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if session.status == .failed {
                Label("All files failed — see the Failed section below for the reason.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
            if session.status == .partial {
                Label("Partial backup — file limit reached. Run again to continue.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if session.incompleteMirror {
                Label("Incomplete mirror — only one SSD was available",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Summary (compact)

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Source", value: sourceName)
            LabeledContent("Destination", value: destinationNames)
            LabeledContent("Folder", value: folderOrgName)
            HStack(spacing: 0) {
                statCell(value: session.files.count, label: "Scanned", color: .primary)
                Divider()
                statCell(value: copiedFiles.count,  label: "Copied",  color: .green)
                Divider()
                statCell(value: skippedFiles.count, label: "Skipped", color: .orange)
                Divider()
                statCell(value: failedFiles.count,  label: "Failed",
                         color: failedFiles.isEmpty ? .secondary : .red)
            }
            .frame(height: 52)
            if !copiedFiles.isEmpty {
                LabeledContent("SHA-256") {
                    let verified = verifiedCount
                    let total    = copiedFiles.count
                    Label(
                        verified == total ? "All \(verified) verified" : "\(verified) / \(total) verified",
                        systemImage: "checkmark.shield.fill"
                    )
                    .foregroundStyle(verified == total ? Color.teal : Color.orange)
                    .font(.subheadline)
                }
            }
            LabeledContent("Data / Duration") {
                Text("\(ByteCountFormatter.string(fromByteCount: totalBytesCopied, countStyle: .file)) · \(durationString)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCell(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Files (navigation links)

    @ViewBuilder
    private var filesSection: some View {
        if !copiedFiles.isEmpty || !skippedFiles.isEmpty || !failedFiles.isEmpty {
            Section("Files") {
                if !copiedFiles.isEmpty {
                    NavigationLink {
                        ReportFilesListView(title: "Copied", files: copiedFiles, color: .green)
                    } label: {
                        fileNavRow("Copied", count: copiedFiles.count, color: .green)
                    }
                }
                if !skippedFiles.isEmpty {
                    NavigationLink {
                        ReportSkippedListView(files: skippedFiles)
                    } label: {
                        fileNavRow("Skipped", count: skippedFiles.count, color: .orange)
                    }
                }
                if !failedFiles.isEmpty {
                    NavigationLink {
                        ReportFailedListView(files: failedFiles, commonError: commonErrorNote)
                    } label: {
                        fileNavRow("Failed", count: failedFiles.count, color: .red)
                    }
                }
            }
        }
    }

    private func fileNavRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(count)")
                .foregroundStyle(color)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Computed

    private var sourceName: String {
        if !session.sourceDisplayName.isEmpty { return session.sourceDisplayName }
        guard let first = session.sources.first else { return "—" }
        return first == "photos-library://local" ? "Photos Library" : URL(fileURLWithPath: first).lastPathComponent
    }

    private var destinationNames: String {
        if !session.destinationDisplayNames.isEmpty {
            return session.destinationDisplayNames.joined(separator: ", ")
        }
        return session.destinations
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .joined(separator: ", ")
    }

    private var folderOrgName: String {
        FolderOrganization(rawValue: session.folderOrganizationRaw)?.displayName ?? "By Date"
    }

    private var copiedFiles:  [IndexedFile] { session.files.filter { $0.copyStatus == .copied  } }
    private var skippedFiles: [IndexedFile] { session.files.filter { $0.copyStatus == .skipped } }
    private var failedFiles:  [IndexedFile] { session.files.filter { $0.copyStatus == .failed  } }
    private var verifiedCount: Int         { copiedFiles.filter { $0.verificationPassed == true }.count }

    private var totalBytesCopied: Int64 {
        copiedFiles.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    private var durationString: String {
        guard let end = session.completedAt else { return "—" }
        return String(format: "%.1f s", end.timeIntervalSince(session.startedAt))
    }

    private var reportHTMLURL: URL? {
        let fm   = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("PhotoVideoBackup/Reports")
        let name = "session_\(session.id)"
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix(name) && $0.pathExtension == "html" }
    }

    private var commonErrorNote: String? {
        let notes = failedFiles.compactMap(\.errorNote)
        guard notes.count == failedFiles.count,
              let first = notes.first,
              notes.allSatisfy({ $0 == first })
        else { return nil }
        return first
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .running:
            Label("Running",   systemImage: "circle.fill").foregroundStyle(.blue)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial:
            Label("Partial",   systemImage: "exclamationmark.arrow.circlepath").foregroundStyle(.orange)
        case .failed:
            Label("Failed",    systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - ReportFilesListView

private struct ReportFilesListView: View {
    let title: String
    let files: [IndexedFile]
    let color: Color

    var body: some View {
        List(files) { file in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).font(.subheadline)
                    if let date = file.captureDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if file.verificationPassed == true {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.teal)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("\(title) (\(files.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ReportSkippedListView

private struct ReportSkippedListView: View {
    let files: [IndexedFile]

    var body: some View {
        List {
            Section {
                Label("Already at destination — same filename and size. No copy needed.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.fileName)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Text(URL(fileURLWithPath: file.sourcePath).deletingLastPathComponent().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Skipped (\(files.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ReportFailedListView

private struct ReportFailedListView: View {
    let files: [IndexedFile]
    let commonError: String?

    var body: some View {
        List {
            if let shared = commonError {
                Section {
                    Label(shared, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(file.fileName, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red).font(.subheadline)
                        if commonError == nil {
                            if let note = file.errorNote {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            } else if let ok = file.verificationPassed, !ok {
                                Text("SHA-256 verification failed")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Failed (\(files.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}
