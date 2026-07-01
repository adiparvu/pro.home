import SwiftUI
import UserNotifications

// MARK: - AutomationRule Model

struct AutomationRule: Identifiable, Codable {
    var id = UUID()
    var name: String
    var triggerIcon: String
    var triggerLabel: String
    var conditionIcon: String
    var conditionLabel: String
    var actionIcon: String
    var actionLabel: String
    var isActive: Bool
    var colorHex: String

    var color: Color { Color(hex: colorHex) ?? .blue }

    init(name: String, triggerIcon: String, triggerLabel: String,
         conditionIcon: String, conditionLabel: String,
         actionIcon: String, actionLabel: String,
         isActive: Bool, color: Color) {
        self.name           = name
        self.triggerIcon    = triggerIcon
        self.triggerLabel   = triggerLabel
        self.conditionIcon  = conditionIcon
        self.conditionLabel = conditionLabel
        self.actionIcon     = actionIcon
        self.actionLabel    = actionLabel
        self.isActive       = isActive
        self.colorHex       = color.hexString()
    }

    static let prvioTemplates: [AutomationRule] = [
        .init(
            name: "Warranty Alert",
            triggerIcon: "shield.lefthalf.filled",
            triggerLabel: "Warranty\nExpires in 30d",
            conditionIcon: "wrench.and.screwdriver.fill",
            conditionLabel: "Appliance\nHas Warranty",
            actionIcon: "bell.badge.fill",
            actionLabel: "Notify &\nCreate Task",
            isActive: true,
            color: Color(red: 0.95, green: 0.45, blue: 0.15)
        ),
        .init(
            name: "Plant Watering",
            triggerIcon: "drop.fill",
            triggerLabel: "Plant Needs\nWater",
            conditionIcon: "sun.max.fill",
            conditionLabel: "Morning\n07:00–09:00",
            actionIcon: "leaf.fill",
            actionLabel: "Mark Plant\nWatered",
            isActive: true,
            color: Color(red: 0.15, green: 0.72, blue: 0.37)
        ),
        .init(
            name: "Task Overdue",
            triggerIcon: "exclamationmark.circle.fill",
            triggerLabel: "Task\nOverdue +1d",
            conditionIcon: "person.fill",
            conditionLabel: "Assigned\nto Me",
            actionIcon: "bell.fill",
            actionLabel: "Send\nReminder",
            isActive: true,
            color: .red
        ),
        .init(
            name: "Document Expiry",
            triggerIcon: "doc.badge.clock.fill",
            triggerLabel: "Document\nExpires in 14d",
            conditionIcon: "exclamationmark.shield.fill",
            conditionLabel: "Is Critical\nDocument",
            actionIcon: "bell.badge.fill",
            actionLabel: "Urgent\nNotification",
            isActive: false,
            color: Color(red: 0.62, green: 0.15, blue: 0.92)
        ),
        .init(
            name: "Irrigation Auto",
            triggerIcon: "humidity.fill",
            triggerLabel: "Soil Moisture\n< 30%",
            conditionIcon: "cloud.rain.fill",
            conditionLabel: "No Rain\nForecast",
            actionIcon: "drop.circle.fill",
            actionLabel: "Start Irrigation\nZone 1",
            isActive: false,
            color: Color(red: 0.25, green: 0.65, blue: 0.55)
        ),
        .init(
            name: "Security Alert",
            triggerIcon: "camera.fill",
            triggerLabel: "Motion\nDetected",
            conditionIcon: "moon.fill",
            conditionLabel: "After\nSunset",
            actionIcon: "bell.fill",
            actionLabel: "Send\nNotification",
            isActive: false,
            color: .orange
        ),
    ]
}

// MARK: - Add Automation Sheet

private struct TriggerOption {
    let label: String
    let icon: String
    let color: Color
}

private struct ConditionOption {
    let label: String
    let icon: String
}

private struct ActionOption {
    let label: String
    let icon: String
}

private struct AutomationPickerRow: View {
    let icon: String
    let label: String
    let accentColor: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct AddAutomationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (AutomationRule) -> Void

    @State private var name = ""
    @State private var triggerType    = 0
    @State private var conditionType  = 0
    @State private var actionType     = 0

    private let triggerOptions: [TriggerOption] = [
        TriggerOption(label: "Warranty expires",       icon: "shield.lefthalf.filled",       color: Color(red: 0.95, green: 0.45, blue: 0.15)),
        TriggerOption(label: "Task overdue",            icon: "exclamationmark.circle.fill",   color: .red),
        TriggerOption(label: "Plant needs water",       icon: "drop.fill",                    color: Color(red: 0.15, green: 0.72, blue: 0.37)),
        TriggerOption(label: "Document expires",        icon: "doc.badge.clock.fill",          color: .purple),
        TriggerOption(label: "Time schedule",           icon: "clock.fill",                   color: .blue),
        TriggerOption(label: "Motion detected",         icon: "camera.fill",                  color: .orange),
        TriggerOption(label: "Appliance service due",   icon: "wrench.and.screwdriver.fill",  color: Color(red: 0.2, green: 0.72, blue: 0.45)),
        TriggerOption(label: "Expense exceeds budget",  icon: "banknote.fill",                color: Color(red: 0.62, green: 0.15, blue: 0.92)),
    ]
    private let conditionOptions: [ConditionOption] = [
        ConditionOption(label: "Always",           icon: "checkmark.circle"),
        ConditionOption(label: "Morning (7–9 AM)", icon: "sunrise.fill"),
        ConditionOption(label: "Evening (6–9 PM)", icon: "sunset.fill"),
        ConditionOption(label: "Weekdays only",    icon: "calendar"),
        ConditionOption(label: "Assigned to me",   icon: "person.fill"),
        ConditionOption(label: "No rain forecast", icon: "cloud.sun.fill"),
    ]
    private let actionOptions: [ActionOption] = [
        ActionOption(label: "Send notification",   icon: "bell.badge.fill"),
        ActionOption(label: "Create task",         icon: "checkmark.circle.fill"),
        ActionOption(label: "Mark as completed",   icon: "checkmark.seal.fill"),
        ActionOption(label: "Log to activity",     icon: "clock.arrow.circlepath"),
        ActionOption(label: "Water plant",         icon: "drop.circle.fill"),
        ActionOption(label: "Add expense note",    icon: "doc.text.fill"),
    ]

    private var selectedTrigger: TriggerOption { triggerOptions[triggerType] }
    private var selectedCondition: ConditionOption { conditionOptions[conditionType] }
    private var selectedAction: ActionOption { actionOptions[actionType] }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Name
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Rule Name")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                TextField("e.g. Warranty Alert", text: $name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Trigger picker
                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("When (Trigger)")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                                ForEach(0..<triggerOptions.count, id: \.self) { i in
                                    AutomationPickerRow(
                                        icon: triggerOptions[i].icon,
                                        label: triggerOptions[i].label,
                                        accentColor: triggerOptions[i].color,
                                        isSelected: triggerType == i
                                    ) {
                                        triggerType = i
                                        HapticFeedback.selection()
                                    }
                                    if i < triggerOptions.count - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 56)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Condition picker
                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("If (Condition)")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                                ForEach(0..<conditionOptions.count, id: \.self) { i in
                                    AutomationPickerRow(
                                        icon: conditionOptions[i].icon,
                                        label: conditionOptions[i].label,
                                        accentColor: Color(red: 0.2, green: 0.55, blue: 0.95),
                                        isSelected: conditionType == i
                                    ) {
                                        conditionType = i
                                        HapticFeedback.selection()
                                    }
                                    if i < conditionOptions.count - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 56)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Action picker
                        GlassCard(padding: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Then (Action)")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                                ForEach(0..<actionOptions.count, id: \.self) { i in
                                    AutomationPickerRow(
                                        icon: actionOptions[i].icon,
                                        label: actionOptions[i].label,
                                        accentColor: .purple,
                                        isSelected: actionType == i
                                    ) {
                                        actionType = i
                                        HapticFeedback.selection()
                                    }
                                    if i < actionOptions.count - 1 {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 56)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("New Automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = selectedTrigger
                        let c = selectedCondition
                        let a = selectedAction
                        let rule = AutomationRule(
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? t.label : name,
                            triggerIcon: t.icon,
                            triggerLabel: t.label,
                            conditionIcon: c.icon,
                            conditionLabel: c.label,
                            actionIcon: a.icon,
                            actionLabel: a.label,
                            isActive: true,
                            color: t.color
                        )
                        onAdd(rule)
                        HapticFeedback.success()
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - AutomationBuilderView

struct AutomationBuilderView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @StateObject private var cloud = GlobalAutomationService()
    @State private var automations: [AutomationRule] = AutomationRule.prvioTemplates
    @State private var activeFlowIndex = 0
    @State private var isDeployed      = false
    @State private var showAdd         = false
    @State private var didLoad         = false

    private func loadFromCloud() async {
        guard !didLoad, let pid = propertyService.primary?.id else { return }
        didLoad = true
        let rules = await cloud.load(propertyId: pid)
        if !rules.isEmpty { automations = rules }
    }

    private func persist() {
        guard let pid = propertyService.primary?.id else { return }
        Task { await cloud.replaceAll(propertyId: pid, rules: automations) }
    }

    private var activeRule: AutomationRule {
        guard automations.indices.contains(activeFlowIndex) else {
            return automations[0]
        }
        return automations[activeFlowIndex]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                statsRow
                flowCanvasCard
                actionBar
                savedSection
                Spacer(minLength: 100)
            }
            .padding(16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Automations")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadFromCloud() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add automation")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddAutomationSheet { rule in
                automations.insert(rule, at: 0)
                activeFlowIndex = 0
                persist()
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        let active = automations.filter(\.isActive).count
        return HStack(spacing: 12) {
            statPill(icon: "bolt.fill", label: "\(automations.count) Rules", color: Color(red: 0.45, green: 0.60, blue: 1.0))
            statPill(icon: "checkmark.circle.fill", label: "\(active) Active", color: Color(red: 0.2, green: 0.78, blue: 0.45))
            statPill(icon: "bell.badge.fill", label: "\(automations.count - active) Paused", color: .orange)
        }
    }

    private func statPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(AppFont.label).foregroundStyle(color)
            Text(label).font(AppFont.caption).foregroundStyle(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: - Flow canvas card

    private var flowCanvasCard: some View {
        let rule = activeRule
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(automations.indices, id: \.self) { i in
                        let a = automations[i]
                        Button {
                            withAnimation(.spring(response: 0.3)) { activeFlowIndex = i }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(a.isActive ? a.color : Color.primary.opacity(0.25))
                                    .frame(width: 6, height: 6)
                                Text(a.name)
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(activeFlowIndex == i ? .white : .secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(
                                activeFlowIndex == i
                                    ? AnyShapeStyle(a.color)
                                    : AnyShapeStyle(Color.primary.opacity(0.08)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .padding(.top, 14).padding(.bottom, 8)

            GeometryReader { geo in
                nodeRedCanvas(rule: rule, width: geo.size.width)
            }
            .frame(height: 260)
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(rule.color.opacity(0.20), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    // MARK: - Node-RED Canvas

    private func nodeRedCanvas(rule: AutomationRule, width: CGFloat) -> some View {
        let nW: CGFloat = min((width - 32) * 0.44, 152)
        let nH: CGFloat = 78
        let gapX: CGFloat = width - 2 * nW
        let topY: CGFloat = 10
        let botY: CGFloat = 170
        let notifyW: CGFloat = min(nW * 0.65, 100)
        let notifyX: CGFloat = nW + gapX * 0.45

        let n1r = CGPoint(x: nW, y: topY + nH / 2)
        let n2l = CGPoint(x: nW + gapX, y: topY + nH / 2)
        let n2r = CGPoint(x: nW + gapX + nW, y: topY + nH / 2)
        let n3r = CGPoint(x: nW, y: botY + nH / 2)
        let n4l = CGPoint(x: notifyX, y: botY + nH / 2)

        return ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let lineColor = GraphicsContext.Shading.color(Color.white.opacity(0.35))
                let dotColor  = GraphicsContext.Shading.color(Color.cyan.opacity(0.85))
                let dotPurple = GraphicsContext.Shading.color(Color.purple.opacity(0.75))

                func line(_ from: CGPoint, _ to: CGPoint) {
                    var p = Path(); p.move(to: from); p.addLine(to: to)
                    ctx.stroke(p, with: lineColor, lineWidth: 1.5)
                }
                func dot(_ pt: CGPoint, _ c: GraphicsContext.Shading) {
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10)), with: c)
                }
                line(n1r, n2l); dot(n1r, dotColor); dot(n2l, dotColor)
                let px = min(n2r.x + 18, size.width - 4)
                var p2 = Path(); p2.move(to: n2r)
                p2.addLine(to: CGPoint(x: px, y: n2r.y))
                p2.addLine(to: CGPoint(x: px, y: n4l.y))
                p2.addLine(to: n4l)
                ctx.stroke(p2, with: lineColor, lineWidth: 1.5)
                dot(n2r, dotColor); dot(n4l, dotPurple)
                line(n3r, n4l); dot(n3r, dotColor)
            }

            flowNode(headerLabel: "When",   bodyText: rule.triggerLabel,   icon: rule.triggerIcon,   color: rule.color)
                .frame(width: nW, height: nH).offset(x: 0, y: topY)
            flowNode(headerLabel: "And",    bodyText: rule.conditionLabel, icon: rule.conditionIcon, color: Color(red: 0.15, green: 0.32, blue: 0.22))
                .frame(width: nW, height: nH).offset(x: nW + gapX, y: topY)
            flowNode(headerLabel: "Then",   bodyText: rule.actionLabel,    icon: rule.actionIcon,    color: Color(red: 0.12, green: 0.28, blue: 0.20))
                .frame(width: nW, height: nH).offset(x: 0, y: botY)
            flowNode(headerLabel: "Notify", bodyText: "User",             icon: "bell.fill",         color: Color(red: 0.18, green: 0.14, blue: 0.30))
                .frame(width: notifyW, height: nH).offset(x: notifyX, y: botY)
        }
    }

    private func flowNode(headerLabel: String, bodyText: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Text(LocalizedStringKey(headerLabel)).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color)

            Text(LocalizedStringKey(bodyText))
                .font(AppFont.captionStrong).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(color.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1))
    }

    // MARK: - Test Automation

    private func testActiveRule() {
        let rule = activeRule
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "[Test] %@"), rule.name)
        content.body = String(format: String(localized: "Trigger: %@ → Action: %@"),
                              rule.triggerLabel.replacingOccurrences(of: "\n", with: " "),
                              rule.actionLabel.replacingOccurrences(of: "\n", with: " "))
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "automation-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        HapticFeedback.success()
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton(icon: "plus", label: "+ Node", color: Color(red: 0.45, green: 0.60, blue: 1.0)) {
                showAdd = true
            }
            actionButton(icon: "play.fill", label: "Test", color: Color(red: 0.2, green: 0.75, blue: 0.45)) {
                testActiveRule()
            }
            Button {
                guard !isDeployed else { return }
                HapticFeedback.success()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { isDeployed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                    withAnimation(.spring(response: 0.4)) { isDeployed = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isDeployed ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                        .font(AppFont.captionStrong)
                    Text(isDeployed ? "Deployed ✓" : "Deploy")
                        .font(AppFont.captionEmphasis)
                }
                .foregroundStyle(isDeployed ? Color(red: 0.20, green: 0.87, blue: 0.48) : Color(red: 0.65, green: 0.45, blue: 0.95))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(
                    (isDeployed ? Color(red: 0.20, green: 0.87, blue: 0.48) : Color(red: 0.65, green: 0.45, blue: 0.95)).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((isDeployed ? Color(red: 0.20, green: 0.87, blue: 0.48) : Color(red: 0.65, green: 0.45, blue: 0.95)).opacity(0.30), lineWidth: 1))
                .animation(.spring(response: 0.35), value: isDeployed)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(AppFont.captionStrong)
                Text(LocalizedStringKey(label)).font(AppFont.captionEmphasis)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Saved list

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Automations")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.primary)
                Spacer()
                Text("\(automations.count)")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }

            ForEach(automations.indices, id: \.self) { i in
                savedRow(i)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            withAnimation {
                                automations.remove(at: i)
                                if activeFlowIndex >= automations.count {
                                    activeFlowIndex = max(0, automations.count - 1)
                                }
                            }
                            persist()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
    }

    private func savedRow(_ index: Int) -> some View {
        let rule = automations[index]
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(rule.color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: rule.triggerIcon)
                    .font(AppFont.subheadline)
                    .foregroundStyle(rule.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                Text("\(rule.triggerLabel.replacingOccurrences(of: "\n", with: " ")) → \(rule.actionLabel.replacingOccurrences(of: "\n", with: " "))")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $automations[index].isActive)
                .toggleStyle(.switch)
                .tint(rule.color)
                .labelsHidden().scaleEffect(0.8)
                .onChange(of: automations[index].isActive) { _, _ in HapticFeedback.selection(); persist() }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(rule.isActive ? rule.color.opacity(0.20) : Color.white.opacity(0.06), lineWidth: 1))
        .opacity(rule.isActive ? 1.0 : 0.6)
        .onTapGesture {
            HapticFeedback.impact(.light)
            withAnimation(.spring(response: 0.3)) { activeFlowIndex = index }
        }
    }
}
