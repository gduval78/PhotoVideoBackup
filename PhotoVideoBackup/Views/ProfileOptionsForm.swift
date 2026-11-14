import SwiftUI

/// A backup's own options — folder structure, file naming, file limit, extra file types — bound to
/// its `ProfileSettings`. Same vocabulary as Settings → Backup, but per backup.
struct ProfileOptionsForm: View {
    @Binding var settings: ProfileSettings
    /// Edited as text, committed digits-only (see CLAUDE.md: never bind a locale-formatted numeric
    /// field straight to storage). Empty or 0 = unlimited.
    @State private var limitText = ""

    var body: some View {
        Section("Backup") {
            Picker("Folder structure", selection: $settings.organization) {
                ForEach(FolderOrganization.allCases, id: \.rawValue) { mode in
                    Text(mode.labelKey).tag(mode.rawValue)
                }
            }
            HStack {
                Text("Max files per session")
                Spacer()
                TextField("Unlimited", text: $limitText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .frame(width: 100)
                    .onChange(of: limitText) { _, new in
                        settings.fileLimit = SettingsView.normalizedFileLimit(from: new)
                    }
            }
            HStack {
                Text("Additional file types")
                Spacer()
                TextField("None", text: $settings.extraExtensions)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .onAppear { limitText = settings.fileLimit > 0 ? String(settings.fileLimit) : "" }

        Section {
            Toggle("Rename files during backup", isOn: $settings.namingEnabled)
            if settings.namingEnabled {
                TextField("Pattern", text: $settings.namingPattern)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(NamingProfile.tokens, id: \.self) { token in
                            Button { settings.namingPattern += token } label: {
                                Text(verbatim: token)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } header: {
            Text("File naming")
        } footer: {
            Text("Each file gets its final name as it is first copied, so it is never stored under its camera name and renamed afterwards. Duplicates are then recognised by that name. Turn off to keep the original file names.")
        }
    }
}
