import SwiftUI

// MARK: - Auto-import deliveries from email
//
// Shows the property's unique forwarding address. The user sets a Gmail filter
// to auto-forward courier/shop shipping emails to it; the backend parses each
// one, creates the delivery and tracks it live. The app only ever shows the
// address — all parsing/provider logic stays server-side.

struct AutoImportView: View {
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(\.dismiss) private var dismiss

    @State private var token: String?
    @State private var loading = true
    @State private var copied = false

    private let domain = "parcelsprv.com"
    private var address: String? { token.map { "\($0)@\(domain)" } }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    hero
                    addressCard
                    steps
                    privacyNote
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .navigationTitle("Auto-import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let pid = deliveryService.currentPropertyId {
                    token = await deliveryService.ensureInbox(propertyId: pid)?.token
                }
                loading = false
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private var hero: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "envelope.badge.fill")
                .font(AppFont.scaled(30, weight: .semibold))
                .foregroundStyle(Color.brandPrimaryBlue)
                .frame(width: 76, height: 76)
                .glassCircle()
            Text("Import deliveries from email")
                .font(AppFont.title2).foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Forward your shipping confirmation emails here and PRVIO adds the delivery and tracks it live — automatically.")
                .font(AppFont.subheadline).foregroundStyle(Color.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.sm)
    }

    private var addressCard: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {
                Text("Your Forwarding Address")
                    .font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                } else if let address {
                    Text(address)
                        .font(AppFont.scaled(16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        UIPasteboard.general.string = address
                        HapticFeedback.success()
                        withAnimation(.snappy) { copied = true }
                        Task { try? await Task.sleep(for: .seconds(2)); withAnimation(AppMotion.state) { copied = false } }
                    } label: {
                        Label(copied ? "Copied" : "Copy address",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(AppFont.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .background(copied ? Color.brandSuccess : Color.brandPrimaryBlue,
                                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Couldn't load your address. Pull to retry.")
                        .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
    }

    private var steps: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("How to Set It Up")
                    .font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                step(1, "Copy the address above.")
                step(2, "In Gmail, open Settings → Filters → Create a filter.")
                step(3, "Match emails from your couriers/shops (e.g. contains \"tracking\", or from dhl.com, sameday.ro…).")
                step(4, "Choose \"Forward to\" and paste this address. Done.")
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text("\(n)")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.brandPrimaryBlue))
            Text(text)
                .font(AppFont.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var privacyNote: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "lock.shield.fill").font(AppFont.footnote).foregroundStyle(Color.brandSuccess)
            Text("We only ever see the emails you choose to forward — never your inbox.")
                .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xs)
    }
}
