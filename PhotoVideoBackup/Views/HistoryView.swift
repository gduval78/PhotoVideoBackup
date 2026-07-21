import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @State private var showClearConfirmation = false
    @State private var logFileSize: Int64? = nil   // nil = file absent
#if DEBUG
    @State private var probeRunning = false
    @State private var probeVerdict: String? = nil
#endif

    var body: some View {
        List {
            if viewModel.sessions.isEmpty {
                ContentUnavailableView(
                    "No Backup History",
                    systemImage: "clock",
                    description: Text("Completed backup sessions will appear here.")
                )
            } else {
                ForEach(viewModel.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                }
            }

            if let size = logFileSize {
                Section("Diagnostic") {
                    NavigationLink {
                        DiagnosticLogView()
                    } label: {
                        HStack {
                            Label("pvb_diagnostic.log", systemImage: "doc.text")
                            Spacer()
                            Text(size.formatted(.byteCount(style: .file)))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteLog()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

#if DEBUG
            // Spike: does evicting a file we wrote into a picked iCloud Drive folder work?
            // DEBUG-only and deliberately unlocalized — this never ships.
            Section("iCloud Eviction Probe (DEBUG)") {
                Button {
                    runEvictionProbe()
                } label: {
                    HStack {
                        Label("Run probe on destinations", systemImage: "icloud.and.arrow.down")
                        Spacer()
                        if probeRunning { ProgressView() }
                    }
                }
                .disabled(probeRunning)

                if let probeVerdict {
                    Text(verbatim: probeVerdict)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
#endif
        }
        .navigationTitle("History")
        .navigationDestination(for: BackupSession.self) { session in
            ReportView(session: session)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.sessions.isEmpty)
            }
        }
        .confirmationDialog("Clear all backup history?", isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { viewModel.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Session records are removed. Files on your SSD are not affected.")
        }
        .onAppear { refreshLogInfo() }
    }

#if DEBUG
    /// Runs the eviction spike against every configured destination and surfaces the verdicts.
    /// Full detail lands in pvb_diagnostic.log under [ICLOUD_PROBE].
    private func runEvictionProbe() {
        probeRunning = true
        probeVerdict = nil
        Task {
            let roots = DestinationManager.shared.resolvedDestinations()
            var lines: [String] = []
            if roots.isEmpty {
                lines.append("No destination configured.")
            }
            for root in roots {
                let result = await ICloudEvictionProbe.run(root: root)
                lines.append("\(root.lastPathComponent): \(result.verdict)")
            }
            probeVerdict = lines.joined(separator: "\n\n")
            probeRunning = false
        }
    }
#endif

    private func refreshLogInfo() {
        let url = DiagnosticLog.logURL
        guard let vals = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = vals.fileSize else { logFileSize = nil; return }
        logFileSize = Int64(size)
    }

    private func deleteLog() {
        try? FileManager.default.removeItem(at: DiagnosticLog.logURL)
        logFileSize = nil
    }
}

// MARK: - DiagnosticLogView

private struct DiagnosticLogView: View {
    @State private var content: String = ""

    var body: some View {
        ScrollView {
            Text(verbatim: content)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Diagnostic Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sendByMail()
                } label: {
                    Image(systemName: "envelope")
                }
                .disabled(content.isEmpty)
            }
        }
        .onAppear {
            content = (try? String(contentsOf: DiagnosticLog.logURL, encoding: .utf8)) ?? ""
        }
    }

    private func sendByMail() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path   = AppConstants.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PhotoVideoBackup \(version) – Diagnostic Log"),
            URLQueryItem(name: "body",    value: content)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - SessionRow

private struct SessionRow: View {
    let session: BackupSession
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(sourceName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(session.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(languageManager.currentLocale)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                (Text(FolderOrganization(rawValue: session.folderOrganizationRaw)?.labelKey ?? "By Date")
                 + Text(verbatim: " · \(session.files.count) ")
                 + Text(session.files.count == 1 ? "file" : "files"))
                .font(.caption)
                .foregroundStyle(.secondary)
                if !destinationText.isEmpty {
                    Label(destinationText, systemImage: "externaldrive.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceName: String {
        if !session.sourceDisplayName.isEmpty { return session.sourceDisplayName }
        guard let first = session.sources.first else { return "—" }
        return first == "photos-library://local"
            ? String(localized: "Photos Library", locale: languageManager.currentLocale)
            : URL(fileURLWithPath: first).lastPathComponent
    }

    private var destinationText: String {
        if !session.destinationDisplayNames.isEmpty {
            return session.destinationDisplayNames.joined(separator: ", ")
        }
        return session.destinations
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .partial:
            Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
