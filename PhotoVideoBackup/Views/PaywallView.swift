import SwiftUI

struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    Spacer(minLength: 20)
                    purchaseSection
                }
                .padding()
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .disabled(store.isLoading)
                }
            }
            .alert("Purchase Error", isPresented: Binding(
                get: { store.purchaseError != nil },
                set: { if !$0 { store.purchaseError = nil } }
            )) {
                Button("OK") { store.purchaseError = nil }
            } message: {
                Text(store.purchaseError ?? "")
            }
            .onChange(of: store.isPremium) { _, isPremium in
                if isPremium { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("PhotoVideoBackup Pro")
                .font(.title2.bold())
            Text("One-time purchase — no subscription")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "photo.on.rectangle.angled",
                color: .blue,
                title: "Photos Library Backup",
                subtitle: "Back up your iPhone photo library to an SSD",
                isFree: true
            )
            Divider().padding(.leading, 50)
            featureRow(
                icon: "plus.circle.fill",
                color: .green,
                title: "Add External Sources",
                subtitle: "SD cards, USB drives, Insta360, DJI, and more",
                isFree: false
            )
            Divider().padding(.leading, 50)
            featureRow(
                icon: "externaldrive.fill",
                color: .purple,
                title: "Second SSD Mirror",
                subtitle: "Redundant backup to a second SSD simultaneously",
                isFree: false
            )
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String, isFree: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(isFree ? "Free" : "Pro")
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isFree ? Color.secondary.opacity(0.2) : Color.yellow.opacity(0.25))
                .foregroundStyle(isFree ? .secondary : .primary)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 14) {
            if store.productLoadFailed {
                VStack(spacing: 10) {
                    Text("Could not load product info.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await store.retryLoadProduct() }
                    } label: {
                        Text("Retry")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isLoadingProduct)
                }
            } else {
            Button {
                Task { await store.purchase() }
            } label: {
                Group {
                    if store.isLoading || store.isLoadingProduct {
                        ProgressView()
                            .tint(.white)
                    } else if let p = store.product {
                        Text("Upgrade for \(p.displayPrice)")
                            .bold()
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isLoading || store.isLoadingProduct || store.product == nil)
            }

            Button {
                Task { await store.restorePurchases() }
            } label: {
                if store.isLoading {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(store.isLoading)

            Text("Payment is charged to your Apple ID at confirmation of purchase.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}
