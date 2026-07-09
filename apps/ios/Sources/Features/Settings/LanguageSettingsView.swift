import SwiftUI

// MARK: - Language settings
//
// PRVIO ships in two languages — Romanian (its native language) and English.
// The screen offers one system toggle ("follow iOS") and, below it, an explicit
// two-language picker. Selecting a language switches the whole app instantly via
// `AppSettings.setLanguage` — no relaunch — because the app root feeds
// `appLocale` into the environment, which re-evaluates every `String(localized:)`.

struct LanguageSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    // Incrementing this forces this screen's subtree to rebuild after a change so
    // its own labels re-read through the newly-active bundle swizzle the instant
    // the user taps, matching the rest of the app.
    @State private var refreshToken = 0

    var body: some View {
        VStack(spacing: 0) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    languagePicker
                    restartNotice
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .id(refreshToken)
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("language_title")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Explicit picker

    private var languagePicker: some View {
        section(title: String(localized: "lang_select_section")) {
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Language.allCases.enumerated()), id: \.element.id) { idx, lang in
                        languageRow(lang, following: appSettings.followSystemLanguage)
                        if idx < Language.allCases.count - 1 {
                            Divider()
                                .overlay(Color.primary.opacity(0.05))
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func languageRow(_ lang: Language, following: Bool) -> some View {
        let isCurrent = appSettings.currentLanguage == lang
        return Button {
            guard appSettings.currentLanguage != lang || following else { return }
            HapticFeedback.selection()
            appSettings.setLanguage(lang)
            refreshToken += 1
        } label: {
            HStack(spacing: 14) {
                Text(lang.flag)
                    .font(AppFont.scaled(30))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.nativeName)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                    Text(lang.localizedName)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isCurrent {
                    if following {
                        Text(String(localized: "lang_follows_ios"))
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(21))
                            .foregroundStyle(Color.accentColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isCurrent)
    }

    // MARK: - Info notice

    private var restartNotice: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.brandPurple)
                    .padding(.top, 1)
                Text(String(localized: "lang_instant_rebuild"))
                    .font(AppFont.scaled(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            content()
        }
    }

    private func iconBadge(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(AppFont.headline)
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Previews

#Preview("English") {
    NavigationStack { LanguageSettingsView() }
        .environment(AppSettings())
        .previewLocalization(.english)
}

#Preview("Romanian") {
    NavigationStack { LanguageSettingsView() }
        .environment(AppSettings())
        .previewLocalization(.romanian)
}
