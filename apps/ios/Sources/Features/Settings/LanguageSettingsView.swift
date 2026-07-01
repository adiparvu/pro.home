import SwiftUI

struct LanguageSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    // Incrementing this forces the entire content subtree to rebuild after a
    // language change, so all String(localized:) calls re-evaluate through the
    // newly-active bundle swizzle.
    @State private var refreshToken = 0

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: String(localized: "language_title"),
                       subtitle: String(localized: "language_subtitle"))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    languageListCard
                    restartNotice
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .id(refreshToken)
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Language list

    private var languageListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "lang_select_section"))
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Language.allCases.enumerated()), id: \.element.id) { idx, lang in
                        Button {
                            HapticFeedback.selection()
                            LanguageManager.apply(lang.rawValue)
                            appSettings.followSystemLanguage = false
                            appSettings.locale = lang.rawValue
                            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
                            UserDefaults.standard.synchronize()
                            refreshToken += 1
                        } label: {
                            HStack(spacing: 14) {
                                Text(lang.flag)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang.nativeName)
                                        .font(AppFont.body)
                                        .foregroundStyle(.primary)
                                    Text(lang.localizedName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appSettings.locale == lang.rawValue {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.base)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if idx < Language.allCases.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, AppSpacing.lg)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Info notice

    private var restartNotice: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text(String(localized: "lang_instant_rebuild"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Previews

#Preview("English") {
    NavigationStack { LanguageSettingsView() }
        .environmentObject(AppSettings())
        .previewLocalization(.english)
}

#Preview("Romanian") {
    NavigationStack { LanguageSettingsView() }
        .environmentObject(AppSettings())
        .previewLocalization(.romanian)
}
