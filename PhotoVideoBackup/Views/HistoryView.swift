import SwiftUI

struct HistoryView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @State private var showClearConfirmation = false

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
    }
}

// MARK: - SessionRow

private struct SessionRow: View {
    let session: BackupSession

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(sourceName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(folderOrgName) · \(session.files.count) files")
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
        return first == "photos-library://local" ? "Photos Library" : URL(fileURLWithPath: first).lastPathComponent
    }

    private var folderOrgName: String {
        FolderOrganization(rawValue: session.folderOrganizationRaw)?.displayName ?? "By Date"
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
