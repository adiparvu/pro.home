import SwiftUI

// MARK: - Settings Group (iOS 26/27 liquid glass)

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
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
                .foregroundStyle(Color.primary.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.07), in: Capsule())
            Spacer()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
