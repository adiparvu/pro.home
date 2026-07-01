import SwiftUI

// MARK: - Settings Group (iOS 26/27 liquid glass)

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) { content }
                .liquidGlass(cornerRadius: 20)
        }
    }
}

// MARK: - Row Variants

struct NavSettingsRow<D: View>: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    @ViewBuilder let destination: () -> D

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                destination()
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: icon, color: color)
                    Text(label)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(AppOpacity.hairline))
                .frame(height: 0.4)
                .padding(.leading, 52)
        }
    }
}

struct TapSettingsRow: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let action: () -> Void
    @State private var iconBounce = false

    var body: some View {
        Button {
            iconBounce.toggle()
            action()
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: color, bounce: iconBounce)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct ToggleSettingsRow: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

struct InfoSettingsRow: View {
    let icon: String
    let color: Color
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.38))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Minimal Icon Badge (monochrome glass, Apple HIG)

struct ColoredIconBadge: View {
    let icon: String
    let color: Color   // kept for API compatibility; not used visually
    var size: CGFloat = 32
    var bounce: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
                }
            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: bounce)
        }
    }
}

// MARK: - Settings Placeholder

struct SettingsPlaceholder: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
            Spacer()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
