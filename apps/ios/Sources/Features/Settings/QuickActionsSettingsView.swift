import SwiftUI

/// Lets the user customize which quick actions appear on the home
/// floating (speed-dial) button.
struct QuickActionsSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettings

    private var enabledCount: Int { appSettings.quickActions.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header

                SettingsGroup(title: "Acțiuni rapide") {
                    ForEach(DashboardQuickAction.allCases) { action in
                        QuickActionToggleRow(
                            action: action,
                            isOn: Binding(
                                get: { appSettings.isQuickActionEnabled(action) },
                                set: { newValue in
                                    HapticFeedback.selection()
                                    appSettings.setQuickAction(action, enabled: newValue)
                                }
                            ),
                            isLast: action == DashboardQuickAction.allCases.last
                        )
                    }
                }

                Text("Acțiunile activate apar pe butonul plutitor de pe ecranul principal, în ordinea de aici.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Buton plutitor")
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
                    Text("Personalizează butonul")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(enabledCount) \(enabledCount == 1 ? "acțiune activă" : "acțiuni active")")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
            }
        }
    }
}

// MARK: - Toggle Row

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
                    .tint(.blue)
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
