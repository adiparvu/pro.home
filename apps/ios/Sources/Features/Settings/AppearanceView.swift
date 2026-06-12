import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                themeSection
                languageSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Theme")

            VStack(spacing: 12) {
                ForEach(AppSettings.themes, id: \.code) { theme in
                    ThemeOptionRow(
                        icon: theme.icon,
                        title: theme.label,
                        isSelected: appSettings.theme == theme.code
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            appSettings.theme = theme.code
                        }
                        if let uid = auth.session?.user.id {
                            appSettings.syncToProfile(userId: uid)
                        }
                    }
                }
            }
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Language")

            VStack(spacing: 0) {
                ForEach(AppSettings.languages, id: \.code) { lang in
                    LanguageOptionRow(
                        flag: lang.flag,
                        name: lang.name,
                        isSelected: appSettings.locale == lang.code
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            appSettings.locale = lang.code
                        }
                        if let uid = auth.session?.user.id {
                            appSettings.syncToProfile(userId: uid)
                        }
                    }

                    if lang.code != AppSettings.languages.last?.code {
                        Rectangle()
                            .fill(.white.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 52)
                    }
                }
            }
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )

            Text("Language changes apply immediately within the app.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.leading, 4)
    }
}

// MARK: - Theme Row

private struct ThemeOptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? .white.opacity(0.18) : .white.opacity(0.07))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Language Row

private struct LanguageOptionRow: View {
    let flag: String
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(flag)
                    .font(.system(size: 26))
                    .frame(width: 40)

                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
