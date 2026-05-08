import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.06), .purple.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                        .padding(.top, 56)

                    Text("PhotoVideoBackup")
                        .font(.largeTitle.bold())

                    Text("Back up your media to an external SSD\nin just a few taps.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 36)

                // Setup diagram
                SetupDiagramView()
                    .padding(.vertical, 28)
                    .padding(.horizontal, 20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)

                // Feature bullets
                VStack(alignment: .leading, spacing: 16) {
                    featureRow(icon: "sdcard.fill",           color: .orange,  text: "SD cards, DJI, Insta360, GoPro and more")
                    featureRow(icon: "externaldrive.fill",    color: .mint,    text: "Direct copy to your USB-C SSD")
                    featureRow(icon: "checkmark.circle.fill", color: .green,   text: "Already-backed-up files are skipped")
                    featureRow(icon: "camera.filters",        color: .purple,  text: "Preview and grade LOG footage with a LUT")
                }
                .padding(.top, 32)
                .padding(.horizontal, 36)

                Spacer()

                // CTA button
                Button {
                    hasSeenOnboarding = true
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
        }
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - SetupDiagramView

private struct SetupDiagramView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            deviceNode(icon: "iphone",         label: "iPhone",  color: .blue)
            arrow
            hubNode
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 6) {
                    arrow
                    deviceNode(icon: "sdcard",         label: "SD Card", color: .orange)
                }
                HStack(spacing: 6) {
                    arrow
                    deviceNode(icon: "externaldrive",  label: "SSD",     color: .mint)
                }
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private var hubNode: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.purple.opacity(0.10))
                    .frame(width: 68, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.purple.opacity(0.30), lineWidth: 1)
                    }
                VStack(spacing: 3) {
                    Image(systemName: "cable.connector")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    Text("USB-C\nHub")
                        .font(.system(size: 9, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.purple)
                }
            }
            Text(" ").font(.caption2)
        }
    }

    private func deviceNode(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
