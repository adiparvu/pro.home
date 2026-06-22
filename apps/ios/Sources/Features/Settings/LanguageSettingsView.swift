import SwiftUI

struct LanguageSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    private let languages: [(name: String, native: String, code: String)] = [
        ("English",    "English",    "en"),
        ("Romanian",   "Română",     "ro"),
        ("French",     "Français",   "fr"),
        ("Dutch",      "Nederlands", "nl"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Language", subtitle: "PREFERENCES")

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
            Text("SYSTEM")
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
                            Text("Use Device Language")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("Follows iOS Settings")
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
            Text("SELECT LANGUAGE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(languages.enumerated()), id: \.element.code) { idx, lang in
                        Button {
                            HapticFeedback.selection()
                            // 1. Swap the bundle strings immediately (no restart needed)
                            LanguageManager.apply(lang.code)
                            // 2. Update AppSettings → triggers .id() rebuild in PRVIOApp
                            appSettings.followSystemLanguage = false
                            appSettings.locale = lang.code
                            // 3. Persist for next launch
                            UserDefaults.standard.set([lang.code], forKey: "AppleLanguages")
                            UserDefaults.standard.synchronize()
                        } label: {
                            HStack(spacing: 14) {
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
                Text("The app rebuilds instantly when you select a language. Some system UI elements may still follow the device language.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
