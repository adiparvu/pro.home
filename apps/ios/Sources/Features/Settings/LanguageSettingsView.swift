import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: String(localized: "language_title"),
                       subtitle: String(localized: "language_subtitle"))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    deviceLanguageCard
                    languageListCard
                    restartNotice
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Device language toggle

    private var deviceLanguageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("lang_system_section")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                Button {
                    HapticFeedback.selection()
                    appSettings.followSystemLanguage = true
                    LanguageManager.reset()
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("lang_use_device")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("lang_follows_ios")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if appSettings.followSystemLanguage {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Language list

    private var languageListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("lang_select_section")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

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
                        } label: {
                            HStack(spacing: 14) {
                                Text(lang.flag)
                                    .font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang.nativeName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(lang.localizedName)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appSettings.locale == lang.rawValue && !appSettings.followSystemLanguage {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if idx < Language.allCases.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 16)
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
                Text("lang_instant_rebuild")
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

#Preview("German") {
    NavigationStack { LanguageSettingsView() }
        .environmentObject(AppSettings())
        .previewLocalization(.german)
}
