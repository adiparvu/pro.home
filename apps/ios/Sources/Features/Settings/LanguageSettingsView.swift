import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    private let languages: [(name: String, native: String, code: String, flag: String)] = [
        ("English",    "English",    "en", "🇬🇧"),
        ("Romanian",   "Română",     "ro", "🇷🇴"),
        ("French",     "Français",   "fr", "🇫🇷"),
        ("Dutch",      "Nederlands", "nl", "🇳🇱"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Language", subtitle: "PREFERENCES")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
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

    // MARK: - Language list

    private var languageListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SELECT LANGUAGE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(languages.enumerated()), id: \.element.code) { idx, lang in
                        Button {
                            HapticFeedback.selection()
                            appSettings.followSystemLanguage = false
                            appSettings.locale = lang.code
                            UserDefaults.standard.set([lang.code], forKey: "AppleLanguages")
                            UserDefaults.standard.synchronize()
                        } label: {
                            HStack(spacing: 14) {
                                Text(lang.flag)
                                    .font(.system(size: 28))
                                    .frame(width: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang.native)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(lang.name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appSettings.locale == lang.code && !appSettings.followSystemLanguage {
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

                        if idx < languages.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 70)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Restart notice

    private var restartNotice: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                Text("Restart the app to fully apply all language changes.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
