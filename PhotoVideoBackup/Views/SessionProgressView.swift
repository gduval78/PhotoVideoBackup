import SwiftUI

struct SessionProgressView: View {
    @Environment(DashboardViewModel.self) private var viewModel
    @Environment(LanguageManager.self)   private var languageManager

    var body: some View {
        GroupBox("Backup in Progress") {
            if let progress = viewModel.currentProgress {
                VStack(alignment: .leading, spacing: 12) {
                    // Mobile-data warning for NAS backups
                    if viewModel.currentBackupUsesNAS && viewModel.isLikelyCellular {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("You appear to be on mobile data. Backing up to the NAS may use your data plan — tap Stop to halt it.")
                                .font(.caption)
                        }
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

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

                    Divider()

                    Button(role: .destructive) {
                        viewModel.requestCancel()
                    } label: {
                        Label(viewModel.isCancelling ? "Stopping…" : "Stop backup",
                              systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isCancelling)
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
        let locale = languageManager.currentLocale
        if seconds < 60 { return String(localized: "< 1 min remaining", locale: locale) }
        let minutes = Int((seconds / 60).rounded())
        return String(localized: "~\(minutes) min remaining", locale: locale)
    }

    private func phaseLabel(_ phase: CopyPhase) -> String {
        let locale = languageManager.currentLocale
        switch phase {
        case .scanning:   return String(localized: "Scanning library…", locale: locale)
        case .exporting:  return String(localized: "Exporting from Photos…", locale: locale)
        case .copying:    return String(localized: "Copying to SSD…", locale: locale)
        case .verifying:  return String(localized: "Verifying…", locale: locale)
        case .done:       return String(localized: "Done", locale: locale)
        case .skipped:    return String(localized: "Already present", locale: locale)
        case .failed(let msg): return String(localized: "Failed: \(msg)", locale: locale)
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
