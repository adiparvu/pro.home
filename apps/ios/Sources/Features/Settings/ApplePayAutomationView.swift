import SwiftUI

// MARK: - Apple Pay → automatic expense tracking (setup guide)
//
// Apple gives no API to read Wallet history, but Shortcuts ships a
// "Transaction" automation trigger that fires on every Apple Pay tap with the
// merchant, amount and card. This page walks the user through wiring that
// trigger to PRVIO's "Log expense" intent — after the one-time setup, every
// payment lands in the household ledger by itself, categorized by merchant.

struct ApplePayAutomationView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header

                VStack(alignment: .leading, spacing: 0) {
                    step(1, "applepay_step_1")
                    step(2, "applepay_step_2")
                    step(3, "applepay_step_3")
                    step(4, "applepay_step_4")
                    step(5, "applepay_step_5")
                    step(6, "applepay_step_6", isLast: true)
                }
                .padding(AppSpacing.lg)
                .liquidGlass(cornerRadius: AppRadius.xl)

                openShortcutsButton

                Text("applepay_privacy_note")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.horizontal, AppSpacing.xxs)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("applepay_integration_title")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "creditcard.and.123")
                    .font(AppFont.scaled(24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.brandSuccess)
                Image(systemName: "arrow.right")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.secondaryTextColor)
                Image(systemName: "chart.pie.fill")
                    .font(AppFont.scaled(24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            Text("applepay_guide_intro")
                .font(AppFont.scaled(14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Text(verbatim: "\(number)")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(AppOpacity.tintedFill), in: Circle())
            Text(text)
                .font(AppFont.scaled(14))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, isLast ? 0 : AppSpacing.base)
    }

    private var openShortcutsButton: some View {
        Button {
            HapticFeedback.impact(.light)
            if let url = URL(string: "shortcuts://") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(AppFont.scaled(15, weight: .semibold))
                Text("applepay_open_shortcuts")
                    .font(AppFont.scaled(15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.base)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
