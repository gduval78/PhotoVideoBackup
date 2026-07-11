import SwiftUI

struct DeleteConfirmationSheet: View {
    let fileCount: Int
    let sourceName: String
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var enteredCode: String = ""
    @State private var isDeleting: Bool = false

    // Generated once when the view is created — stable across re-renders via @State
    @State private var expectedCode: String = String(format: "%04d", Int.random(in: 0...9999))

    private var codeMatches: Bool { enteredCode == expectedCode }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                warningHeader
                codeSection
                deleteButton
                Spacer()
            }
            .padding()
            .navigationTitle("Delete Source Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
    }

    // MARK: - Sections

    private var warningHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            if fileCount == 1 {
                Text("1 file will be permanently deleted from **\(sourceName)**.")
                    .multilineTextAlignment(.center)
                    .font(.headline)
            } else {
                Text("\(fileCount) files will be permanently deleted from **\(sourceName)**.")
                    .multilineTextAlignment(.center)
                    .font(.headline)
            }
            Text("This action cannot be undone. Make sure your backup is complete before proceeding.")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }

    private var codeSection: some View {
        VStack(spacing: 12) {
            Text("Enter this code to confirm deletion:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(expectedCode)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
            TextField("Code", text: $enteredCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .frame(maxWidth: 120)
                .disabled(isDeleting)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var deleteButton: some View {
        Button {
            Task {
                isDeleting = true
                await onConfirm()
                isDeleting = false
                dismiss()
            }
        } label: {
            Group {
                if isDeleting {
                    ProgressView()
                } else if fileCount == 1 {
                    Text("Delete 1 file")
                } else {
                    Text("Delete \(fileCount) files")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!codeMatches || isDeleting)
        .controlSize(.large)
    }
}
