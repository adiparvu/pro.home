import SwiftUI
import UIKit

struct LanguageSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    private let languages: [(name: String, native: String, code: String)] = [
        ("Arabic",                 "العربية",            "ar"),
        ("Catalan",                "Català",              "ca"),
        ("Chinese (Simplified)",   "简体中文",             "zh-Hans"),
        ("Chinese (Traditional)",  "繁體中文",             "zh-Hant"),
        ("Croatian",               "Hrvatski",            "hr"),
        ("Czech",                  "Čeština",             "cs"),
        ("Danish",                 "Dansk",               "da"),
        ("Dutch",                  "Nederlands",          "nl"),
        ("English",                "English",             "en"),
        ("Finnish",                "Suomi",               "fi"),
        ("French",                 "Français",            "fr"),
        ("German",                 "Deutsch",             "de"),
        ("Greek",                  "Ελληνικά",            "el"),
        ("Hebrew",                 "עברית",               "he"),
        ("Hindi",                  "हिन्दी",               "hi"),
        ("Hungarian",              "Magyar",              "hu"),
        ("Indonesian",             "Bahasa Indonesia",    "id"),
        ("Italian",                "Italiano",            "it"),
        ("Japanese",               "日本語",               "ja"),
        ("Korean",                 "한국어",               "ko"),
        ("Malay",                  "Bahasa Melayu",       "ms"),
        ("Norwegian",              "Norsk Bokmål",        "nb"),
        ("Polish",                 "Polski",              "pl"),
        ("Portuguese (Brazil)",    "Português (Brasil)",  "pt-BR"),
        ("Portuguese (Portugal)",  "Português (Portugal)","pt-PT"),
        ("Romanian",               "Română",              "ro"),
        ("Russian",                "Русский",             "ru"),
        ("Slovak",                 "Slovenčina",          "sk"),
        ("Spanish",                "Español",             "es"),
        ("Swedish",                "Svenska",             "sv"),
        ("Thai",                   "ภาษาไทย",             "th"),
        ("Turkish",                "Türkçe",              "tr"),
        ("Ukrainian",              "Українська",          "uk"),
        ("Vietnamese",             "Tiếng Việt",          "vi"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: String(localized: "language_title"),
                       subtitle: String(localized: "language_subtitle"))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    followToggleCard
                    if !appSettings.followSystemLanguage { languageListCard }
                    iosSettingsTip
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

    // MARK: - Follow iOS toggle

    private var followToggleCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "language_follow_ios"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(String(localized: "language_follow_ios_desc"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $appSettings.followSystemLanguage)
                        .labelsHidden()
                        .onChange(of: appSettings.followSystemLanguage) { _, follows in
                            if follows { HapticFeedback.success() }
                            else { HapticFeedback.impact(.light) }
                        }
                }

                if !appSettings.followSystemLanguage {
                    Divider()
                    HStack {
                        Text(String(localized: "language_current"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(currentNativeName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    // MARK: - Language list

    private var languageListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "language_select"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(languages.enumerated()), id: \.element.code) { idx, lang in
                        Button {
                            HapticFeedback.selection()
                            appSettings.locale = lang.code
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
                                if appSettings.locale == lang.code {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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

    // MARK: - iOS Settings tip

    private var iosSettingsTip: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                    Text("To change the app language, go to iOS Settings → PRVIO → Language. The app needs to restart to apply the change.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gear")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open iOS Settings")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var currentNativeName: String {
        languages.first(where: { $0.code == appSettings.locale })?.native
            ?? Locale(identifier: appSettings.locale).localizedString(forLanguageCode: appSettings.locale)
            ?? appSettings.locale
    }
}
