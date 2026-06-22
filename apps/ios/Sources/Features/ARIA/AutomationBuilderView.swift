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
            triggerIcon: "humidity.fill",
            triggerLabel: "Soil Moisture\n< 30%",
            conditionIcon: "cloud.rain.fill",
            conditionLabel: "No Rain\nForecast",
            actionIcon: "drop.circle.fill",
            actionLabel: "Start Irrigation\nZone 1",
            isActive: true,
            color: Color(red: 0.25, green: 0.65, blue: 0.55)
        ),
        .init(
            name: "Pool Pump",
            triggerIcon: "clock.fill",
            triggerLabel: "Daily\nat 8:00",
            conditionIcon: "drop.fill",
            conditionLabel: "pH\n< 7.0",
            actionIcon: "bolt.fill",
            actionLabel: "Run Pump\n2 hours",
            isActive: true,
            color: .cyan
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
        .init(
            name: "Greenhouse Vent",
            triggerIcon: "thermometer",
            triggerLabel: "Temp\n> 25°C",
            conditionIcon: "humidity.fill",
            conditionLabel: "Humidity\n> 80%",
            actionIcon: "wind",
            actionLabel: "Open\nVents",
            isActive: true,
            color: .green
        ),
    ]
}

// MARK: - AutomationBuilderView

struct AutomationBuilderView: View {
    @State private var automations: [AutomationRule] = AutomationRule.examples
    @State private var activeFlowIndex: Int = 0
    @State private var showPreviewAlert = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                previewBanner
                headerCard
                // Main visual flow canvas (Node-RED style)
                flowCanvasCard
                // Bottom action bar
                actionBar
                // Saved automations
                savedSection
                Spacer(minLength: 100)
            }
            .padding(16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Automation Builder")
        .navigationBarTitleDisplayMode(.large)
        .alert("Feature Preview", isPresented: $showPreviewAlert) {
            Button("OK") {}
        } message: {
            Text("Automation rules are coming in an upcoming update. You can design flows here to preview the builder.")
        }
    }

    private var previewBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.95))
            Text("Feature Preview — automation rules coming soon")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.95))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Header

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
                Text("Visual automation with Node-RED power")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Node-RED Flow Canvas

    private var flowCanvasCard: some View {
        let rule = automations[activeFlowIndex]
        return VStack(spacing: 0) {
            // Rule selector chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(automations.indices, id: \.self) { i in
                        let a = automations[i]
                        Button {
                            withAnimation(.spring(response: 0.3)) { activeFlowIndex = i }
                        } label: {
                            Text(a.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(activeFlowIndex == i ? .white : .secondary)
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
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Canvas with nodes and connecting lines
            GeometryReader { geo in
                nodeRedCanvas(rule: rule, width: geo.size.width)
            }
            .frame(height: 260)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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

    // MARK: - Node-RED Canvas Drawing

    private func nodeRedCanvas(rule: AutomationRule, width: CGFloat) -> some View {
        let nW: CGFloat = min((width - 32) * 0.44, 152)
        let nH: CGFloat = 78
        let gapX: CGFloat = width - 2 * nW  // horizontal gap between columns
        let topY: CGFloat = 10
        let botY: CGFloat = 170
        let notifyW: CGFloat = min(nW * 0.65, 100)
        let notifyX: CGFloat = nW + gapX * 0.45  // Notify node x offset

        // Connector centers (right/left edges)
        let n1r = CGPoint(x: nW, y: topY + nH / 2)
        let n2l = CGPoint(x: nW + gapX, y: topY + nH / 2)
        let n2r = CGPoint(x: nW + gapX + nW, y: topY + nH / 2)
        let n3r = CGPoint(x: nW, y: botY + nH / 2)
        let n4l = CGPoint(x: notifyX, y: botY + nH / 2)

        return ZStack(alignment: .topLeading) {
            // Lines + dots
            Canvas { ctx, size in
                let lineColor = GraphicsContext.Shading.color(Color.white.opacity(0.35))
                let dotColor = GraphicsContext.Shading.color(Color.cyan.opacity(0.85))
                let dotColorPurple = GraphicsContext.Shading.color(Color.purple.opacity(0.75))

                // Line 1: N1.right → N2.left
                var p1 = Path()
                p1.move(to: n1r)
                p1.addLine(to: n2l)
                ctx.stroke(p1, with: lineColor, lineWidth: 1.5)

                // Connector dot N1.right
                let d1 = CGRect(x: n1r.x - 5, y: n1r.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: d1), with: dotColor)
                // Connector dot N2.left
                let d2 = CGRect(x: n2l.x - 5, y: n2l.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: d2), with: dotColor)

                // Line 2: N2.right → right angle → N4.left
                let pivotX = min(n2r.x + 18, size.width - 4)
                var p2 = Path()
                p2.move(to: n2r)
                p2.addLine(to: CGPoint(x: pivotX, y: n2r.y))
                p2.addLine(to: CGPoint(x: pivotX, y: n4l.y))
                p2.addLine(to: n4l)
                ctx.stroke(p2, with: lineColor, lineWidth: 1.5)

                // Connector dot N2.right
                let d3 = CGRect(x: n2r.x - 5, y: n2r.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: d3), with: dotColor)
                // Connector dot N4.left (purple for notify)
                let d4 = CGRect(x: n4l.x - 5, y: n4l.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: d4), with: dotColorPurple)

                // Line 3: N3.right → N4.left
                var p3 = Path()
                p3.move(to: n3r)
                p3.addLine(to: n4l)
                ctx.stroke(p3, with: lineColor, lineWidth: 1.5)

                // Connector dot N3.right
                let d5 = CGRect(x: n3r.x - 5, y: n3r.y - 5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: d5), with: dotColor)
            }

            // Node 1: Trigger
            flowNode(
                headerLabel: "When",
                bodyText: rule.triggerLabel,
                icon: rule.triggerIcon,
                color: rule.color
            )
            .frame(width: nW, height: nH)
            .offset(x: 0, y: topY)

            // Node 2: Condition
            flowNode(
                headerLabel: "And",
                bodyText: rule.conditionLabel,
                icon: rule.conditionIcon,
                color: Color(red: 0.15, green: 0.32, blue: 0.22)
            )
            .frame(width: nW, height: nH)
            .offset(x: nW + gapX, y: topY)

            // Node 3: Action
            flowNode(
                headerLabel: "Then",
                bodyText: rule.actionLabel,
                icon: rule.actionIcon,
                color: Color(red: 0.12, green: 0.28, blue: 0.20)
            )
            .frame(width: nW, height: nH)
            .offset(x: 0, y: botY)

            // Node 4: Notify User
            flowNode(
                headerLabel: "Notify",
                bodyText: "User",
                icon: "bell.fill",
                color: Color(red: 0.18, green: 0.14, blue: 0.30)
            )
            .frame(width: notifyW, height: nH)
            .offset(x: notifyX, y: botY)
        }
    }

    private func flowNode(headerLabel: String, bodyText: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(headerLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color)

            // Body
            Text(bodyText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(color.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Action Bar (+ Node / Test / Deploy)

    private var actionBar: some View {
        HStack(spacing: 10) {
            actionButton(icon: "plus", label: "+ Node", color: Color(red: 0.45, green: 0.60, blue: 1.0))
            actionButton(icon: "play.fill", label: "Test", color: Color(red: 0.2, green: 0.75, blue: 0.45))
            Button {
                HapticFeedback.impact(.medium)
                showPreviewAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 12, weight: .semibold))
                    Text("Deploy").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.65, green: 0.45, blue: 0.95))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(red: 0.65, green: 0.45, blue: 0.95).opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(icon: String, label: String, color: Color) -> some View {
        Button {
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Saved Automations

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Automations")
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
                savedRow(automations[i], index: i)
            }
        }
    }

    private func savedRow(_ rule: AutomationRule, index: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(rule.color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: rule.triggerIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(rule.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(rule.triggerLabel.replacingOccurrences(of: "\n", with: " ")) → \(rule.actionLabel.replacingOccurrences(of: "\n", with: " "))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $automations[index].isActive)
                .toggleStyle(SwitchToggleStyle(tint: rule.color))
                .labelsHidden()
                .scaleEffect(0.8)
                .onChange(of: automations[index].isActive) { _, _ in
                    HapticFeedback.selection()
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(rule.isActive ? rule.color.opacity(0.20) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(rule.isActive ? 1.0 : 0.6)
        .onTapGesture {
            HapticFeedback.impact(.light)
            withAnimation(.spring(response: 0.3)) { activeFlowIndex = index }
        }
    }
}
