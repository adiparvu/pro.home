import SwiftUI

// MARK: - AutomationRule Model

struct AutomationRule: Identifiable {
    let id = UUID()
    var name: String
    var triggerIcon: String
    var triggerLabel: String
    var conditionIcon: String
    var conditionLabel: String
    var actionIcon: String
    var actionLabel: String
    var isActive: Bool
    var color: Color

    static let examples: [AutomationRule] = [
        .init(
            name: "Irrigation Auto",
            triggerIcon: "thermometer",
            triggerLabel: "Temp > 28°C",
            conditionIcon: "clock.fill",
            conditionLabel: "Between 6-9 AM",
            actionIcon: "drop.fill",
            actionLabel: "Start Irrigation",
            isActive: true,
            color: .blue
        ),
        .init(
            name: "Pool Pump",
            triggerIcon: "clock.fill",
            triggerLabel: "Daily at 8:00",
            conditionIcon: "drop.fill",
            conditionLabel: "pH < 7.0",
            actionIcon: "bolt.fill",
            actionLabel: "Run Pump 2h",
            isActive: true,
            color: .cyan
        ),
        .init(
            name: "Security Alert",
            triggerIcon: "camera.fill",
            triggerLabel: "Motion Detected",
            conditionIcon: "moon.fill",
            conditionLabel: "After Sunset",
            actionIcon: "bell.fill",
            actionLabel: "Send Notification",
            isActive: false,
            color: .orange
        ),
        .init(
            name: "Greenhouse Vent",
            triggerIcon: "thermometer",
            triggerLabel: "Temp > 25°C",
            conditionIcon: "humidity.fill",
            conditionLabel: "Humidity > 80%",
            actionIcon: "wind",
            actionLabel: "Open Vents",
            isActive: true,
            color: .green
        ),
    ]
}

// MARK: - AutomationBuilderView

struct AutomationBuilderView: View {
    @State private var automations: [AutomationRule] = AutomationRule.examples
    @State private var showAddAutomation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerCard
                automationsList
                addButton
                Spacer(minLength: 100)
            }
            .padding(16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("PRVIO Intelligence")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
                Text("Automate your property with trigger-condition-action rules.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Automations List

    private var automationsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Automations")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(automations.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }

            ForEach(automations.indices, id: \.self) { i in
                automationCard(automations[i], index: i)
            }
        }
    }

    private func automationCard(_ automation: AutomationRule, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(automation.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: automation.triggerIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(automation.color)
                }
                Text(automation.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: .constant(automation.isActive))
                    .toggleStyle(SwitchToggleStyle(tint: automation.color))
                    .labelsHidden()
                    .scaleEffect(0.85)
            }

            HStack(spacing: 6) {
                flowStep(
                    icon: automation.triggerIcon,
                    label: "TRIGGER",
                    value: automation.triggerLabel,
                    color: automation.color
                )

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)

                flowStep(
                    icon: automation.conditionIcon,
                    label: "WHEN",
                    value: automation.conditionLabel,
                    color: .orange
                )

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)

                flowStep(
                    icon: automation.actionIcon,
                    label: "ACTION",
                    value: automation.actionLabel,
                    color: .green
                )
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    automation.isActive
                        ? automation.color.opacity(0.25)
                        : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .opacity(automation.isActive ? 1.0 : 0.6)
    }

    private func flowStep(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: Circle())
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            showAddAutomation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("New Automation")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 1.0))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 0.45, green: 0.60, blue: 1.0).opacity(0.4), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}
