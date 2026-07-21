import SwiftUI

// MARK: - "For you" — the ProactiveEngine's insights, back on the dashboard
//
// The engine has computed rule-based insights (warranty expiries, financial
// month-over-month swings, task momentum, seasonal hints, appliance age)
// since the "visible intelligence" phase — but nothing on the home tab
// showed them. One rotating card fixes that: a slow 8-second cycle through
// the active insights with a per-insight dismiss, and an honest "all clear"
// line when the engine has nothing to say.

struct ProactiveInsightsCard: View {
    var compact: Bool = false

    @Environment(ProactiveEngine.self) private var engine
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rotation cursor — kept valid by clamping against the live count.
    @State private var cursor = 0

    var body: some View {
        let insights = engine.activeInsights
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("For you")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer()
                if insights.count > 1 {
                    Text(verbatim: "\(currentIndex(insights.count) + 1)/\(insights.count)")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if insights.isEmpty {
                Text("All clear — nothing needs attention.")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(.secondary)
            } else {
                let insight = insights[currentIndex(insights.count)]
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: insight.category.icon)
                        .font(AppFont.scaled(17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: insight.title)
                            .font(AppFont.scaled(14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if !compact {
                            Text(verbatim: insight.body)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: AppSpacing.xs)
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                            engine.dismiss(insight)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .accessibilityLabel(Text("Dismiss"))
                }
                .id(insight.id)
                .transition(.opacity)
                // The proactive bridge: an insight is not just news — it can
                // become work. Long-press turns it into a real task (the
                // engine's fact as title, its reasoning as description) or
                // opens the assistant with the question already composed.
                .contextMenu {
                    if insight.category != .financial {
                        Button {
                            addAsTask(insight)
                        } label: {
                            Label("Add as task", systemImage: "checklist")
                        }
                    }
                    Button {
                        askAssistant(insight)
                    } label: {
                        Label("Ask the assistant", systemImage: "sparkles")
                    }
                }
            }
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
        .task(id: insights.count > 1) {
            // The slow rotation lives only while ≥2 insights exist; the task
            // cancels itself whenever the condition flips.
            guard insights.count > 1, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.4)) { cursor += 1 }
            }
        }
    }

    private func currentIndex(_ count: Int) -> Int {
        count > 0 ? cursor % count : 0
    }

    /// The insight becomes a pending maintenance task and leaves the card —
    /// it graduated from advice to plan.
    private func addAsTask(_ insight: ProactiveInsight) {
        guard let pid = propertyService.primary?.id else { return }
        Task {
            let payload = NewTaskPayload(
                propertyId: pid,
                title: insight.title,
                description: insight.body,
                dueDate: nil,
                priority: insight.category == .warranty ? "high" : "medium",
                category: "maintenance",
                assigneeIds: [],
                assigneeNames: [])
            if (try? await taskService.addTask(payload)) != nil {
                HapticFeedback.success()
                engine.dismiss(insight)
            } else {
                HapticFeedback.error()
            }
        }
    }

    /// Opens the assistant with the question already composed from the
    /// insight — the user reviews and sends, nothing fires on its own.
    private func askAssistant(_ insight: ProactiveInsight) {
        UserDefaults.standard.set(
            String(format: String(localized: "aria_insight_prompt_fmt"),
                   insight.title, insight.body),
            forKey: "prvio.aria.pendingPrompt")
        router.navigate(to: .aria)
    }
}

// MARK: - Property value — the sparkline widget

struct PropertyValueSparkWidget: View {
    let action: () -> Void

    @Environment(PropertyValueService.self) private var valueService

    /// Oldest → newest for the sparkline's left-to-right time axis.
    private var series: [Double] {
        valueService.sortedEntries.reversed().suffix(12).map(\.valueAmount)
    }

    /// Percent change of the latest entry against the one before it.
    private var delta: Double? {
        let values = series
        guard values.count >= 2, let last = values.last,
              let previous = values.dropLast().last, previous != 0 else { return nil }
        return (last - previous) / previous * 100
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    if series.count >= 2 {
                        sparkline
                            .frame(width: 64, height: 30)
                    } else {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(AppFont.scaled(22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    if let delta {
                        Text(verbatim: String(format: "%+.1f%%", delta))
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(delta >= 0 ? Color.brandSuccess : Color.brandDanger)
                            .monospacedDigit()
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(valueText)
                        .font(AppFont.scaled(22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Property value")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text("Property value"))
        .accessibilityValue(Text(verbatim: valueText))
    }

    private var valueText: String {
        guard let latest = valueService.latestValue else { return "–" }
        let amount = latest.valueAmount.formatted(.number.precision(.fractionLength(0)))
        return "\(amount) \(CurrencyService.symbol(for: latest.currency))"
    }

    private var subtitleText: String {
        valueService.latestValue == nil
            ? String(localized: "no valuations yet")
            : String(localized: "latest estimate")
    }

    /// A tiny min–max-normalized line — real entries only, no smoothing
    /// invention beyond connecting the actual points.
    private var sparkline: some View {
        let values = series
        return GeometryReader { geo in
            let lo = values.min() ?? 0
            let hi = values.max() ?? 1
            let span = max(hi - lo, 0.000001)
            let stepX = geo.size.width / CGFloat(max(values.count - 1, 1))
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
