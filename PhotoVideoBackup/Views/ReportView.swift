import SwiftUI

struct ReportView: View {
    let session: BackupSession

    var body: some View {
        List {
            headerSection
            summarySection

            if !copiedFiles.isEmpty  { fileSection("Copied",  files: copiedFiles,  color: .green)  }
            if !skippedFiles.isEmpty { fileSection("Skipped", files: skippedFiles, color: .orange) }
            if !failedFiles.isEmpty  { failedSection }
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

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack {
                statusBadge
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if session.incompleteMirror {
                Label("Incomplete mirror — only one SSD was available",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Total scanned", value: "\(session.files.count)")
            LabeledContent("Copied") {
                Text("\(copiedFiles.count)").foregroundStyle(.green)
            }
            LabeledContent("Skipped") {
                Text("\(skippedFiles.count)").foregroundStyle(.orange)
            }
            LabeledContent("Failed") {
                Text("\(failedFiles.count)")
                    .foregroundStyle(failedFiles.isEmpty ? Color.secondary : Color.red)
            }
            LabeledContent("Data copied",
                           value: ByteCountFormatter.string(fromByteCount: totalBytesCopied, countStyle: .file))
            LabeledContent("Duration", value: durationString)
        }
    }

    private func fileSection(_ title: String, files: [IndexedFile], color: Color) -> some View {
        Section("\(title) (\(files.count))") {
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName)
                        .font(.subheadline)
                    if let date = file.captureDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var failedSection: some View {
        Section("Failed (\(failedFiles.count))") {
            ForEach(failedFiles) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Label(file.fileName, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    if let ok = file.verificationPassed, !ok {
                        Text("SHA-256 verification failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Computed

    private var copiedFiles:  [IndexedFile] { session.files.filter { $0.copyStatus == .copied  } }
    private var skippedFiles: [IndexedFile] { session.files.filter { $0.copyStatus == .skipped } }
    private var failedFiles:  [IndexedFile] { session.files.filter { $0.copyStatus == .failed  } }

    private var totalBytesCopied: Int64 {
        copiedFiles.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    private var durationString: String {
        guard let end = session.completedAt else { return "—" }
        return String(format: "%.1f s", end.timeIntervalSince(session.startedAt))
    }

    private var reportHTMLURL: URL? {
        // Run synchronously — ReportBuilder stores files in Documents/
        let fm  = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("PhotoVideoBackup/Reports")
        let name = "session_\(session.id)"
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return nil }
        return files.first { $0.lastPathComponent.hasPrefix(name) && $0.pathExtension == "html" }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.status {
        case .running:
            Label("Running", systemImage: "circle.fill").foregroundStyle(.blue)
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
