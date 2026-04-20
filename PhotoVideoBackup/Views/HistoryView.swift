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
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text("\(session.files.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
