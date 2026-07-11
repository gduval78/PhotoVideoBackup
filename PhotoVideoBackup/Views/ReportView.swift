import SwiftUI

struct ReportView: View {
    let session: BackupSession

    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)    private var languageManager
    @State private var showDeleteSheet = false
    @State private var deletionResult: DeletionResult? = nil
    @State private var showDeletionAlert = false

    var body: some View {
        List {
            headerSection
            summarySection
            filesSection
            deleteSection
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
        .sheet(isPresented: $showDeleteSheet) {
            DeleteConfirmationSheet(
                fileCount: copiedFiles.count,
                sourceName: sourceName
            ) {
                let result = await SourceDeletionManager.deleteFiles(
                    copiedFiles,
                    externalSources: viewModel.externalSources
                )
                await MainActor.run {
                    deletionResult = result
                    showDeletionAlert = true
                }
            }
        }
        .alert("Deletion Complete", isPresented: $showDeletionAlert, presenting: deletionResult) { _ in
            Button("OK", role: .cancel) {}
        } message: { result in
            if result.nothingToDelete {
                Text("These files have already been deleted.")
            } else if result.failed == 0 {
                if result.deleted == 1 {
                    Text("\(result.deleted) file deleted successfully.")
                } else {
                    Text("\(result.deleted) files deleted successfully.")
                }
            } else {
                Text("\(result.deleted) deleted, \(result.failed) failed.")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            HStack {
                statusBadge
                Spacer()
                Text(session.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(languageManager.currentLocale)))
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

    // MARK: - Summary

    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Source", value: sourceName)
            LabeledContent("Folder", value: folderOrgName)
            LabeledContent("Data / Duration") {
                Text("\(totalBytesCopied.formatted(.byteCount(style: .file).locale(languageManager.currentLocale))) · \(durationString)")
                    .foregroundStyle(.secondary)
            }
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
            // Per-target breakdown — one row per destination SSD.
            ForEach(Array(targetSummaries().enumerated()), id: \.offset) { _, target in
                VStack(alignment: .leading, spacing: 4) {
                    Label(target.displayName, systemImage: "externaldrive.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 0) {
                        statCell(value: target.copied,  label: "Copied",  color: .green)
                        Divider()
                        statCell(value: target.skipped, label: "Skipped", color: .orange)
                        Divider()
                        statCell(value: target.failed,  label: "Failed",
                                 color: target.failed == 0 ? .secondary : .red)
                    }
                    .frame(height: 44)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func statCell(value: Int, label: LocalizedStringKey, color: Color) -> some View {
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

    // MARK: - Per-target summary computation

    struct TargetSummary {
        let displayName: String
        var copied  = 0
        var skipped = 0
        var failed  = 0
    }

    private func targetSummaries() -> [TargetSummary] {
        session.destinations.enumerated().map { idx, root in
            let name = idx < session.destinationDisplayNames.count
                ? session.destinationDisplayNames[idx]
                : URL(fileURLWithPath: root).lastPathComponent
            var t = TargetSummary(displayName: name)
            for file in session.files {
                let present = file.destinationPaths.contains { $0.hasPrefix(root) }
                if present {
                    if file.copyStatus == .skipped { t.skipped += 1 } else { t.copied += 1 }
                } else if file.copyStatus != .pending {
                    t.failed += 1
                }
            }
            return t
        }
    }

    // MARK: - Delete section

    @ViewBuilder
    private var deleteSection: some View {
        if canDelete {
            Section {
                Button(role: .destructive) {
                    showDeleteSheet = true
                } label: {
                    Label("Delete Source Files…", systemImage: "trash")
                }
            } footer: {
                Text("Permanently deletes the \(copiedFiles.count) files that were copied during this session from the original source. Your backup is not affected.")
            }
        }
    }

    private var canDelete: Bool {
        SourceDeletionManager.canDelete(
            session: session,
            copiedFiles: copiedFiles,
            externalSources: viewModel.externalSources
        )
    }

    // MARK: - Files (navigation links)

    @ViewBuilder
    private var filesSection: some View {
        let allFiles = session.files.filter { $0.copyStatus != .pending }
        if !allFiles.isEmpty {
            Section("Files") {
                if session.destinations.count > 1 {
                    // Multi-destination: single unified list with per-target status.
                    NavigationLink {
                        ReportMultiTargetFilesView(files: allFiles, session: session)
                    } label: {
                        fileNavRow("All files", count: allFiles.count, color: .primary)
                    }
                } else {
                    // Single destination: keep the classic split by status.
                    if !copiedFiles.isEmpty {
                        NavigationLink {
                            ReportFilesListView(title: String(localized: "Copied", locale: languageManager.currentLocale), files: copiedFiles, color: .green)
                        } label: {
                            fileNavRow("Copied", count: copiedFiles.count, color: .green)
                        }
                    }
                    if !skippedFiles.isEmpty {
                        NavigationLink {
                            ReportSkippedListView(files: skippedFiles, session: session)
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
    }

    private func fileNavRow(_ label: LocalizedStringKey, count: Int, color: Color) -> some View {
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
        return first == "photos-library://local"
            ? String(localized: "Photos Library", locale: languageManager.currentLocale)
            : URL(fileURLWithPath: first).lastPathComponent
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
        (FolderOrganization(rawValue: session.folderOrganizationRaw) ?? .byDate)
            .localizedDisplayName(locale: languageManager.currentLocale)
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
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        List(files) { file in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.fileName).font(.subheadline)
                    if let date = file.captureDate {
                        Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(languageManager.currentLocale)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(file.fileSize.formatted(.byteCount(style: .file).locale(languageManager.currentLocale)))
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
    let session: BackupSession
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        List {
            Section {
                Label("Files already present on every destination — no copy needed.",
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(files) { file in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.fileName)
                            .font(.subheadline)
                        ForEach(Array(destRows(for: file).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(row.color)
                                Image(systemName: "externaldrive.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(row.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(file.fileSize.formatted(.byteCount(style: .file).locale(languageManager.currentLocale)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .navigationTitle("Skipped (\(files.count))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct DestRow {
        let name: String
        let color: Color
    }

    private func destRows(for file: IndexedFile) -> [DestRow] {
        session.destinations.enumerated().map { idx, root in
            let displayName = idx < session.destinationDisplayNames.count
                ? session.destinationDisplayNames[idx]
                : URL(fileURLWithPath: root).lastPathComponent

            // Check if any stored destination path belongs to this root.
            let matchingPath = file.destinationPaths.first { $0.hasPrefix(root) }
            guard let path = matchingPath else {
                return DestRow(name: displayName, color: .red)
            }
            // Green = exact physical match (sha256 empty = physical skip).
            // Orange = found by SHA-256 (possibly renamed at destination).
            let byHash = !file.sha256.isEmpty
            _ = path  // path confirmed to exist at record time
            return DestRow(name: displayName, color: byHash ? .orange : .green)
        }
    }
}

// MARK: - ReportMultiTargetFilesView

private struct ReportMultiTargetFilesView: View {
    let files: [IndexedFile]
    let session: BackupSession
    @Environment(LanguageManager.self) private var languageManager

    private struct DestInfo { let root: String; let name: String }

    private var destinations: [DestInfo] {
        session.destinations.enumerated().map { idx, root in
            let name = idx < session.destinationDisplayNames.count
                ? session.destinationDisplayNames[idx]
                : URL(fileURLWithPath: root).lastPathComponent
            return DestInfo(root: root, name: name)
        }
    }

    var body: some View {
        List(files) { file in
            VStack(alignment: .leading, spacing: 4) {
                // Filename
                Text(file.fileName)
                    .font(.subheadline)
                // Per-target status row
                ForEach(destinations, id: \.root) { dest in
                    let status = perTargetStatus(file: file, root: dest.root)
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(status.color)
                        Image(systemName: "externaldrive.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(dest.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(status.label)
                            .font(.caption2)
                            .foregroundStyle(status.color)
                    }
                }
                // File size + date
                HStack {
                    Text(file.fileSize.formatted(.byteCount(style: .file).locale(languageManager.currentLocale)))
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let date = file.captureDate {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
                            .locale(languageManager.currentLocale)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 3)
        }
        .navigationTitle("Files (\(files.count))")
        .navigationBarTitleDisplayMode(.inline)
    }

    private struct PerTargetStatus {
        let color: Color
        let label: LocalizedStringKey
    }

    private func perTargetStatus(file: IndexedFile, root: String) -> PerTargetStatus {
        let present = file.destinationPaths.contains { $0.hasPrefix(root) }
        if present {
            switch file.copyStatus {
            case .copied:  return PerTargetStatus(color: .green,    label: "Copied")
            case .skipped: return PerTargetStatus(color: .orange,   label: "Skipped")
            default:       return PerTargetStatus(color: .green,    label: "Copied")
            }
        } else {
            return PerTargetStatus(color: .red, label: "Failed")
        }
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
