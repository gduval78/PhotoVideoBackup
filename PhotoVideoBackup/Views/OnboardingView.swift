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
                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "sdcard.fill",           color: .orange,  text: "SD cards, DJI, Insta360, GoPro and more")
                    featureRow(icon: "externaldrive.fill",    color: .mint,    text: "Direct copy to your USB-C SSD")
                    featureRow(icon: "checkmark.circle.fill", color: .green,   text: "Already-backed-up files are skipped")
                    featureRow(icon: "camera.filters",        color: .purple,  text: "Preview and grade LOG footage with a LUT")
                    featureRow(icon: "pencil.and.list.clipboard", color: .blue,    text: "Batch rename files with date & index tokens")
                    featureRow(icon: "icloud",                   color: .cyan,    text: "Back up to iCloud Drive, SSD, or both at once")
                    featureRow(icon: "externaldrive.connected.to.line.below", color: .indigo, text: "Back up over Wi-Fi to a NAS — even remotely")
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body)
                .frame(width: 26)
            Text(text)
                .font(.footnote)
        }
    }
}

// MARK: - SetupDiagramView (carousel)

private struct SetupDiagramView: View {
    @State private var page = 0
    @State private var dragOffset: CGFloat = 0

    private let diagrams: [(title: String, content: AnyView)] = [
        ("Simple",        AnyView(BasicDiagram())),
        ("Hub",           AnyView(HubDiagram())),
        ("iCloud + SSD",  AnyView(ICloudDiagram())),
        ("Advanced",      AnyView(AdvancedDiagram())),
        ("NAS",           AnyView(NASDiagram())),
    ]

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(diagrams.indices, id: \.self) { i in
                        VStack(spacing: 8) {
                            Text(diagrams[i].title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            diagrams[i].content
                        }
                        .frame(width: geo.size.width)
                    }
                }
                .offset(x: -CGFloat(page) * geo.size.width + dragOffset)
                .animation(.easeInOut(duration: 0.28), value: page)
                .gesture(
                    DragGesture()
                        .onChanged { v in dragOffset = v.translation.width }
                        .onEnded { v in
                            let threshold = geo.size.width * 0.25
                            withAnimation(.easeInOut(duration: 0.28)) {
                                if v.translation.width < -threshold, page < diagrams.count - 1 { page += 1 }
                                else if v.translation.width > threshold, page > 0 { page -= 1 }
                                dragOffset = 0
                            }
                        }
                )
            }
            .frame(height: diagramHeight)

            // Page dots
            HStack(spacing: 6) {
                ForEach(diagrams.indices, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.blue : Color.secondary.opacity(0.35))
                        .frame(width: i == page ? 7 : 5, height: i == page ? 7 : 5)
                        .animation(.easeInOut, value: page)
                }
            }
        }
    }

    private var diagramHeight: CGFloat {
        switch page {
        case 0: return 90
        case 1, 2: return 110
        case 3: return 165
        default: return 100   // NAS
        }
    }
}

// MARK: - Diagram 1 — Basic (iPhone → SSD direct)

private struct BasicDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DiagramNode(icon: "iphone",          label: "iPhone",  color: .blue,   size: 32)
            DiagramArrow()
            DiagramNode(icon: "externaldrive",   label: "SSD",     color: .mint,   size: 32)
        }
    }
}

// MARK: - Diagram 2 — Hub (iPhone → Hub → SD Card + SSD)

private struct HubDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DiagramNode(icon: "iphone", label: "iPhone", color: .blue, size: 28)
            DiagramArrow()
            HubNode()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    DiagramArrow()
                    DiagramNode(icon: "sdcard",        label: "SD Card", color: .orange, size: 24)
                }
                HStack(spacing: 8) {
                    DiagramArrow()
                    DiagramNode(icon: "externaldrive", label: "SSD",     color: .mint,   size: 24)
                }
            }
        }
    }
}

// MARK: - Diagram 3 — iCloud + SSD

private struct ICloudDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DiagramNode(icon: "iphone", label: "iPhone", color: .blue, size: 28)
            DiagramArrow()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    DiagramArrow()
                    DiagramNode(icon: "icloud",        label: "iCloud Drive", color: .cyan, size: 24)
                }
                HStack(spacing: 8) {
                    DiagramArrow()
                    DiagramNode(icon: "externaldrive", label: "SSD",          color: .mint, size: 24)
                }
            }
        }
    }
}

// MARK: - Diagram 4 — Advanced (iPhone → Hub → Battery + SD + SSD USB-A + SSD USB-C)

private struct AdvancedDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            DiagramNode(icon: "iphone", label: "iPhone", color: .blue, size: 22)
            DiagramArrow()
            HubNode()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    DiagramArrow()
                    DiagramNode(icon: "battery.100",    label: "Battery",    color: .yellow, size: 15)
                }
                HStack(spacing: 4) {
                    DiagramArrow()
                    DiagramNode(icon: "sdcard",         label: "SD Card",    color: .orange, size: 15)
                }
                HStack(spacing: 4) {
                    DiagramArrow()
                    DiagramNode(icon: "externaldrive",  label: "SSD USB-A",  color: .mint,   size: 15)
                }
                HStack(spacing: 4) {
                    DiagramArrow()
                    DiagramNode(icon: "externaldrive",  label: "SSD USB-C",  color: .teal,   size: 15)
                }
            }
        }
    }
}

// MARK: - Diagram 5 — NAS (iPhone → Wi-Fi / VPN → NAS over the network)

private struct NASDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DiagramNode(icon: "iphone", label: "iPhone", color: .blue, size: 30)
            VStack(spacing: 1) {
                Image(systemName: "wifi")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("Wi-Fi / VPN")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            DiagramNode(icon: "server.rack", label: "NAS", color: .indigo, size: 30)
        }
    }
}

// MARK: - Shared primitives

private struct DiagramArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

private struct DiagramNode: View {
    let icon: String
    let label: String
    let color: Color
    let size: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 44)
    }
}

private struct HubNode: View {
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.purple.opacity(0.10))
                    .frame(width: 58, height: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.purple.opacity(0.30), lineWidth: 1)
                    }
                VStack(spacing: 2) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 16))
                        .foregroundStyle(.purple)
                    Text("USB-C\nHub")
                        .font(.system(size: 8, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.purple)
                }
            }
            Text(" ").font(.system(size: 8))
        }
    }
}
