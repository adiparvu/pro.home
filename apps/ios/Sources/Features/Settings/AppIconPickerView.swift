import SwiftUI

// MARK: - App Icon Picker

struct AppIconPickerView: View {
    @Environment(IconManager.self) private var iconManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showError = false
    @State private var errorMsg = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "App Icon", subtitleKey: "PERSONALIZATION")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    currentIconPreview
                    autoSwitchToggle
                    iconGrid
                    noticeCard
                    Spacer(minLength: 110)
                }
                .padding(.top, AppSpacing.lg)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Icon not available", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(errorMsg))
        }
    }

    // MARK: - Current preview

    private var currentIconPreview: some View {
        let group = iconManager.selectedGroup
        return VStack(spacing: 10) {
            HStack(spacing: 20) {
                iconSquare(group, scheme: .light, size: 68)
                if group.hasPair {
                    iconSquare(group, scheme: .dark, size: 68)
                }
            }
            Text(LocalizedStringKey(group.displayName))
                .font(AppFont.footnoteEmphasis)
            if group.hasPair {
                HStack(spacing: 4) {
                    Image(systemName: "sun.min").font(.system(size: 10))
                    Text("Light").font(.system(size: 11))
                    Spacer().frame(width: 12)
                    Image(systemName: "moon").font(.system(size: 10))
                    Text("Dark").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            } else {
                Text("Standalone — same in both modes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auto-switch toggle

    private var autoSwitchToggle: some View {
        @Bindable var iconManager = iconManager
        return GlassCard(padding: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: "wand.and.stars")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Dark/Light Switch")
                        .font(AppFont.footnoteEmphasis)
                    Text("Icon changes automatically with system theme")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $iconManager.autoSwitch)
                    .tint(.purple)
                    .labelsHidden()
            }
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Grid

    private var iconGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AppIconThemeGroup.allCases) { group in
                iconCell(group)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func iconCell(_ group: AppIconThemeGroup) -> some View {
        let isSelected = iconManager.selectedGroup == group
        return Button {
            applyGroup(group)
        } label: {
            GlassCard(padding: 16) {
                VStack(spacing: 12) {
                    HStack(spacing: group.hasPair ? 12 : 0) {
                        iconSquare(group, scheme: .light, size: 52)
                        if group.hasPair {
                            iconSquare(group, scheme: .dark, size: 52)
                        }
                    }
                    HStack {
                        Text(LocalizedStringKey(group.displayName))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.system(size: 18))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    if group.hasPair {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                            Text("Auto L/D")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // MARK: - Icon square preview

    private func iconSquare(_ group: AppIconThemeGroup, scheme: ColorScheme, size: CGFloat) -> some View {
        let colors = scheme == .light ? group.lightColors : group.darkColors
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
        .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 8, y: 4)
    }

    // MARK: - Notice

    private var noticeCard: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Icons in progress")
                        .font(AppFont.captionEmphasis)
                    Text("Final icon designs are being finalized. Changes activate once the app assets are published.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Apply

    private func applyGroup(_ group: AppIconThemeGroup) {
        HapticFeedback.selection()
        iconManager.select(group, isDark: colorScheme == .dark)
    }
}
