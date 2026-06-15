import SwiftUI

// MARK: - Icon definition

struct AppIconOption: Identifiable {
    let id: String          // alternateIconName; "default" → nil
    let name: String
    let lightColors: [Color]
    let darkColors: [Color]

    static let all: [AppIconOption] = [
        AppIconOption(id: "default",        name: "Classic",
                      lightColors: [Color(red:0.18,green:0.51,blue:1.0), Color(red:0.08,green:0.38,blue:0.9)],
                      darkColors:  [Color(red:0.1,green:0.28,blue:0.9),  Color(red:0.05,green:0.15,blue:0.7)]),
        AppIconOption(id: "AppIconMidnight", name: "Midnight",
                      lightColors: [Color(red:0.06,green:0.08,blue:0.2),  Color(red:0.02,green:0.04,blue:0.14)],
                      darkColors:  [Color(red:0.04,green:0.06,blue:0.18), Color(red:0.01,green:0.02,blue:0.1)]),
        AppIconOption(id: "AppIconSunset",   name: "Sunset",
                      lightColors: [Color(red:1.0,green:0.55,blue:0.15), Color(red:0.9,green:0.2,blue:0.2)],
                      darkColors:  [Color(red:0.85,green:0.35,blue:0.05), Color(red:0.7,green:0.1,blue:0.1)]),
        AppIconOption(id: "AppIconForest",   name: "Forest",
                      lightColors: [Color(red:0.12,green:0.52,blue:0.28), Color(red:0.06,green:0.32,blue:0.16)],
                      darkColors:  [Color(red:0.08,green:0.38,blue:0.2),  Color(red:0.04,green:0.22,blue:0.1)]),
        AppIconOption(id: "AppIconLavender", name: "Lavender",
                      lightColors: [Color(red:0.6,green:0.38,blue:0.95), Color(red:0.45,green:0.2,blue:0.85)],
                      darkColors:  [Color(red:0.5,green:0.28,blue:0.88), Color(red:0.35,green:0.12,blue:0.75)]),
        AppIconOption(id: "AppIconRoseGold", name: "Rose Gold",
                      lightColors: [Color(red:0.95,green:0.58,blue:0.68), Color(red:0.82,green:0.62,blue:0.28)],
                      darkColors:  [Color(red:0.82,green:0.42,blue:0.55), Color(red:0.68,green:0.48,blue:0.18)]),
        AppIconOption(id: "AppIconArctic",   name: "Arctic",
                      lightColors: [Color(red:0.62,green:0.88,blue:0.98), Color(red:0.38,green:0.72,blue:0.92)],
                      darkColors:  [Color(red:0.42,green:0.68,blue:0.88), Color(red:0.22,green:0.52,blue:0.78)]),
        AppIconOption(id: "AppIconCarbon",   name: "Carbon",
                      lightColors: [Color(red:0.2,green:0.2,blue:0.22),  Color(red:0.1,green:0.1,blue:0.12)],
                      darkColors:  [Color(red:0.14,green:0.14,blue:0.16), Color(red:0.06,green:0.06,blue:0.08)]),
        AppIconOption(id: "AppIconCrimson",  name: "Crimson",
                      lightColors: [Color(red:0.82,green:0.08,blue:0.14), Color(red:0.62,green:0.04,blue:0.08)],
                      darkColors:  [Color(red:0.68,green:0.04,blue:0.1),  Color(red:0.48,green:0.02,blue:0.06)]),
        AppIconOption(id: "AppIconEmerald",  name: "Emerald",
                      lightColors: [Color(red:0.05,green:0.72,blue:0.62), Color(red:0.02,green:0.52,blue:0.44)],
                      darkColors:  [Color(red:0.02,green:0.58,blue:0.48), Color(red:0.01,green:0.38,blue:0.32)]),
    ]
}

// MARK: - Picker view

struct AppIconPickerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("prvio.selectedIcon") private var selectedIconId: String = "default"
    @State private var pendingChange: String? = nil
    @State private var showError = false
    @State private var errorMsg = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "App Icon", subtitle: "PERSONALIZATION")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    currentIconPreview

                    Text("Choose one of the 10 available icons.\nEach has variants for light and dark mode.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AppIconOption.all) { option in
                            iconCell(option)
                        }
                    }
                    .padding(.horizontal, 20)

                    noticeCard

                    Spacer(minLength: 110)
                }
                .padding(.top, 16)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Icon not available", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMsg)
        }
    }

    // MARK: Current preview

    private var currentIconPreview: some View {
        let option = AppIconOption.all.first { $0.id == selectedIconId } ?? AppIconOption.all[0]
        return VStack(spacing: 10) {
            HStack(spacing: 20) {
                iconSquare(option, scheme: .light, size: 68)
                iconSquare(option, scheme: .dark, size: 68)
            }
            Text(option.name)
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 4) {
                Image(systemName: "sun.min")
                    .font(.system(size: 10))
                Text("Light")
                    .font(.system(size: 11))
                Spacer().frame(width: 12)
                Image(systemName: "moon")
                    .font(.system(size: 10))
                Text("Dark")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Icon cell

    private func iconCell(_ option: AppIconOption) -> some View {
        let isSelected = selectedIconId == option.id
        return Button { applyIcon(option) } label: {
            GlassCard(padding: 16) {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        iconSquare(option, scheme: .light, size: 52)
                        iconSquare(option, scheme: .dark, size: 52)
                    }
                    HStack {
                        Text(option.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 18))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // MARK: Icon square preview

    private func iconSquare(_ option: AppIconOption, scheme: ColorScheme, size: CGFloat) -> some View {
        let colors = scheme == .light ? option.lightColors : option.darkColors
        let bg = scheme == .light ? Color.white.opacity(0.08) : Color.black.opacity(0.12)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Image(systemName: "house.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 8, y: 4)
    }

    // MARK: Notice

    private var noticeCard: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Icons in progress")
                        .font(.system(size: 13, weight: .semibold))
                    Text("The final icon designs are being worked on. The change will be active once they are published.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: Apply

    private func applyIcon(_ option: AppIconOption) {
        HapticFeedback.selection()
        let name: String? = option.id == "default" ? nil : option.id
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error = error {
                errorMsg = "The icon \"\(option.name)\" is not available yet. We will notify you when all variants are ready.\n\n(\(error.localizedDescription))"
                showError = true
            } else {
                withAnimation { selectedIconId = option.id }
                HapticFeedback.success()
            }
        }
    }
}
