import SwiftUI

struct SessionProgressView: View {
    @Environment(DashboardViewModel.self) private var viewModel

    var body: some View {
        GroupBox("Backup in Progress") {
            if let progress = viewModel.currentProgress {
                VStack(alignment: .leading, spacing: 12) {
                    // Overall
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Overall Progress")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(Int(progress.overallProgress * 100)) %")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress.overallProgress)
                            .progressViewStyle(.linear)
                        HStack {
                            Text("\(fileIndex(progress)) / \(progress.totalFiles) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let eta = viewModel.estimatedSecondsRemaining, eta > 5 {
                                Spacer()
                                Text(etaLabel(eta))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Current file
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            phaseIcon(progress.phase)
                            Text(progress.fileName)
                                .font(.body.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        ProgressView(value: progress.fileProgress)
                            .progressViewStyle(.linear)
                            .tint(phaseColor(progress.phase))
                        Text(phaseLabel(progress.phase))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            } else {
                ProgressView("Initializing…")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding(.horizontal)
    }

    private func fileIndex(_ p: CopyProgress) -> Int { p.fileIndex + 1 }

    private func etaLabel(_ seconds: Double) -> String {
        if seconds < 60 { return "< 1 min remaining" }
        let minutes = Int((seconds / 60).rounded())
        return "~\(minutes) min remaining"
    }

    private func phaseLabel(_ phase: CopyPhase) -> String {
        switch phase {
        case .scanning:   return "Scanning library…"
        case .exporting:  return "Exporting from Photos…"
        case .copying:    return "Copying to SSD…"
        case .verifying:  return "Verifying…"
        case .done:       return "Done"
        case .skipped:    return "Already present"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    @ViewBuilder
    private func phaseIcon(_ phase: CopyPhase) -> some View {
        switch phase {
        case .scanning:   Image(systemName: "photo.on.rectangle").foregroundStyle(.purple)
        case .exporting:  Image(systemName: "arrow.up.doc").foregroundStyle(.blue)
        case .copying:    Image(systemName: "arrow.down.doc").foregroundStyle(.green)
        case .verifying:  Image(systemName: "checkmark.shield").foregroundStyle(.orange)
        case .done:       Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:    Image(systemName: "minus.circle").foregroundStyle(.gray)
        case .failed:     Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private func phaseColor(_ phase: CopyPhase) -> Color {
        switch phase {
        case .scanning:  return .purple
        case .exporting: return .blue
        case .copying:   return .green
        case .verifying: return .orange
        case .done:      return .green
        case .skipped:   return .gray
        case .failed:    return .red
        }
    }
}
