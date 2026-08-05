import SwiftUI

// MARK: - What's-new tour (once per build)
//
// The release tour: on the FIRST foreground after an update — never on a
// fresh install, where there is nothing "new" to compare against — a sheet
// lists this train's highlights and gets out of the way. The last-seen build
// (CFBundleVersion) lives in UserDefaults; MainTabView's foreground beat asks
// `WhatsNew.shouldPresent()` and mounts the sheet, nothing else.

enum WhatsNew {

    struct Highlight: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    /// This train's highlights — the ONE array to edit per release.
    static let current: [Highlight] = [
        Highlight(id: "dossier",
                  icon: "shippingbox.fill",
                  tint: .brandPrimaryBlue,
                  title: "whatsnew_dossier_title",
                  body: "whatsnew_dossier_body"),
        Highlight(id: "currency",
                  icon: "creditcard.fill",
                  tint: .brandSuccess,
                  title: "whatsnew_currency_title",
                  body: "whatsnew_currency_body"),
        Highlight(id: "photos",
                  icon: "photo.on.rectangle.angled",
                  tint: .brandPurple,
                  title: "whatsnew_photos_title",
                  body: "whatsnew_photos_body"),
        Highlight(id: "budget",
                  icon: "gauge.with.needle",
                  tint: .brandWarning,
                  title: "whatsnew_budget_title",
                  body: "whatsnew_budget_body")
    ]

    private static let lastSeenBuildKey = "prvio.whatsNew.lastSeenBuild"

    private static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// True exactly once per build — and never on a first install: with no
    /// previously-stored build there was no update, so the tour stays quiet
    /// and simply remembers where it starts counting from.
    static func shouldPresent() -> Bool {
        let build = currentBuild
        guard !build.isEmpty, !current.isEmpty else { return false }
        guard let seen = UserDefaults.standard.string(forKey: lastSeenBuildKey) else {
            UserDefaults.standard.set(build, forKey: lastSeenBuildKey)
            return false
        }
        return seen != build
    }

    /// Stamped the moment the sheet appears (not on dismiss), so a mid-tour
    /// termination can never replay the tour on the next launch.
    static func markSeen() {
        UserDefaults.standard.set(currentBuild, forKey: lastSeenBuildKey)
    }
}

// MARK: - The sheet

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                header
                highlightList
                GlassWideButton(label: "whatsnew_continue") { dismiss() }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xxl)
            .padding(.bottom, AppSpacing.xl)
        }
        .sheetGround()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { WhatsNew.markSeen() }
    }

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "sparkles")
                .font(AppFont.scaled(34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            Text("whatsnew_title")
                .font(AppFont.scaled(26, weight: .bold))
                .multilineTextAlignment(.center)
            Text("whatsnew_subtitle")
                .font(AppFont.scaled(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var highlightList: some View {
        VStack(spacing: 0) {
            ForEach(Array(WhatsNew.current.enumerated()), id: \.element.id) { idx, highlight in
                highlightRow(highlight)
                if idx < WhatsNew.current.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 0.5)
                        .padding(.leading, 58)
                }
            }
        }
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    private func highlightRow(_ highlight: WhatsNew.Highlight) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: highlight.icon)
                .font(AppFont.footnoteEmphasis)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(highlight.tint)
                .frame(width: 32, height: 32)
                .glassCircle()
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.title)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(highlight.body)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }
}
