import SwiftUI

// MARK: - Theme (Settings → Aspect → Temă)
//
// The living mood backdrop was RETIRED (user-decreed, 2026-07-19) — this
// page is the classic theme control again: Automatic (follows the device),
// Light, Dark. It keeps the historical type name so the Aspect hub's
// navigation row needed no re-wiring.

struct BackgroundMoodView: View {
    private var engine: AppMoodEngine { .shared }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SettingsGroup(title: "appearance_title") {
                    VStack(spacing: 0) {
                        ForEach(Array(AppAppearance.allCases.enumerated()), id: \.element) { index, mode in
                            if index > 0 { rowDivider }
                            themeRow(mode)
                        }
                    }
                }
                Text("theme_page_caption")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.sm)
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("appearance_title"))
        .navigationBarTitleDisplayMode(.large)
    }

    private func themeRow(_ mode: AppAppearance) -> some View {
        Button {
            guard engine.appearance != mode else { return }
            engine.appearance = mode
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon(for: mode),
                                 color: engine.appearance == mode ? .accentColor : Color.primary.opacity(0.4))
                Text(mode.titleKey)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Spacer()
                if engine.appearance == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(engine.appearance == mode ? .isSelected : [])
    }

    private func icon(for mode: AppAppearance) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54)
    }
}
