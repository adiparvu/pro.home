import SwiftUI

/// Lets the user customize the floating (speed-dial) button on each page:
/// which quick actions appear, and whether the button shows at all.
struct QuickActionsSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header

                ForEach(FloatingButtonHost.allCases) { host in
                    hostSection(host)
                }

                Text("If a page has a single active action, the button triggers it directly. With multiple actions, the button opens a menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Floating Buttons")
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 46, height: 46)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Customize buttons")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Choose which actions appear on each page — or hide the button entirely.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
            }
        }
    }

    private func hostSection(_ host: FloatingButtonHost) -> some View {
        let visible = appSettings.fabVisible(host)
        return VStack(alignment: .leading, spacing: 8) {
            Text(host.title)
                .textCase(.uppercase)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            VStack(spacing: 0) {
                FabVisibilityRow(
                    isOn: Binding(
                        get: { appSettings.fabVisible(host) },
                        set: { newValue in
                            HapticFeedback.selection()
                            appSettings.setFabVisible(host, newValue)
                        }
                    ),
                    isLast: !visible
                )

                if visible {
                    ForEach(DashboardQuickAction.allCases) { action in
                        QuickActionToggleRow(
                            action: action,
                            isOn: Binding(
                                get: { appSettings.isFabActionEnabled(host, action) },
                                set: { newValue in
                                    HapticFeedback.selection()
                                    appSettings.setFabAction(host, action, enabled: newValue)
                                }
                            ),
                            isLast: action == DashboardQuickAction.allCases.last
                        )
                    }
                }
            }
            .liquidGlass(cornerRadius: 20)
        }
    }
}

// MARK: - Rows

private struct FabVisibilityRow: View {
    @Binding var isOn: Bool
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: isOn ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text("Show button")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.4)
                    .padding(.leading, 58)
            }
        }
    }
}

private struct QuickActionToggleRow: View {
    let action: DashboardQuickAction
    @Binding var isOn: Bool
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(action.color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: action.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(action.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(action.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.4)
                    .padding(.leading, 58)
            }
        }
    }
}
