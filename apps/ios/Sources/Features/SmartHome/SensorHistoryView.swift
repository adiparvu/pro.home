import SwiftUI
import Charts
import Observation

// MARK: - Sensor history (Smart Control R4)
//
// The living half of a sensor: a Swift Charts line over the sensor's
// `iot_events` rows — webhook events posted by the user's own controllers
// plus the HomeKit readings the app mirrors (IoTService+History). One
// 30-day query with an explicit limit feeds all three period chips
// (24 h / 7 z / 30 z); a chip exists ONLY when its window actually holds
// data (honesty law — no empty promises). Latest / min / max are computed
// from the real points of the selected window, formatted with the
// sensor's own unit.

// MARK: Target — what the chart is about

/// One history-capable reading stream, provider-agnostic: an IoT hub
/// sensor (`sensor.id`), or a HomeKit accessory metric mirrored under
/// `IoTService.homeKitSensorId`.
struct SensorHistoryTarget: Identifiable {
    /// The `iot_events.sensor_id` this stream accrues under.
    let id: String
    let name: String
    /// Fallback unit when a row carries none (the sensor's configured unit).
    let unit: String
    let tint: Color
}

// MARK: Freshness (shared honesty threshold)

/// When a "latest value" stops being presentable as live: readings older
/// than this gain a quiet relative timestamp wherever they surface, so
/// stale never masquerades as current.
enum SensorFreshness {
    static let staleAfter: TimeInterval = 24 * 3_600

    static func isStale(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) > staleAfter
    }
}

// MARK: Periods

enum SensorHistoryPeriod: CaseIterable, Identifiable {
    case day, week, month
    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day:   86_400
        case .week:  7 * 86_400
        case .month: 30 * 86_400
        }
    }

    /// "24 h / 7 z / 30 z" (RO) — localized period chip labels.
    var title: String {
        switch self {
        case .day:   String(localized: "sh_history_24h")
        case .week:  String(localized: "sh_history_7d")
        case .month: String(localized: "sh_history_30d")
        }
    }
}

// MARK: Model — one 30-day load per presented sensor

@MainActor
@Observable
final class SensorHistoryModel {
    enum Phase { case loading, loaded, failed }

    private(set) var phase: Phase = .loading
    /// Every fetched point (oldest-first) with a numeric value.
    private(set) var points: [IoTHistoryPoint] = []
    /// True when the query's explicit cap bit — the fetched set is honestly
    /// only the NEWEST slice of the window.
    private(set) var isTruncated = false

    let sensorId: String

    init(sensorId: String) {
        self.sensorId = sensorId
    }

    func load() async {
        phase = .loading
        do {
            let rows = try await IoTService.shared.sensorHistory(sensorId: sensorId)
            isTruncated = rows.count >= IoTService.historyQueryLimit
            points = rows.filter { $0.value != nil }
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    /// The chips that may be offered: only periods whose window holds at
    /// least one point. When the fetch was truncated, a period whose start
    /// lies before the oldest fetched row can't be drawn honestly — it is
    /// withheld rather than rendered incomplete.
    var availablePeriods: [SensorHistoryPeriod] {
        guard let newest = points.last?.createdAt else { return [] }
        let coverageStart = isTruncated ? (points.first?.createdAt ?? newest) : .distantPast
        return SensorHistoryPeriod.allCases.filter { period in
            let start = Date().addingTimeInterval(-period.duration)
            guard newest >= start else { return false }
            return start >= coverageStart || !isTruncated
        }
    }

    func points(in period: SensorHistoryPeriod) -> [IoTHistoryPoint] {
        let start = Date().addingTimeInterval(-period.duration)
        return points.filter { $0.createdAt >= start }
    }
}

// MARK: Section — the embeddable history card

struct SensorHistorySection: View {
    let target: SensorHistoryTarget

    @State private var model: SensorHistoryModel
    @State private var selected: SensorHistoryPeriod? = nil
    /// Non-nil when the presenting PAGE owns the period selection — folded
    /// into its one filter circle (one-circle law) — so the card header
    /// stays naked. Embedded cards (space page tiles) keep their own
    /// in-card chips: there the row is a segment tied to one chart card,
    /// not page chrome.
    private let externalSelection: Binding<SensorHistoryPeriod?>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(target: SensorHistoryTarget) {
        self.target = target
        _model = State(initialValue: SensorHistoryModel(sensorId: target.id))
        externalSelection = nil
    }

    /// The sheet's variant: the page injects the model it observes (its
    /// filter circle needs the honest available periods) and the selection
    /// binding its circle drives.
    init(target: SensorHistoryTarget, model: SensorHistoryModel,
         selection: Binding<SensorHistoryPeriod?>) {
        self.target = target
        _model = State(initialValue: model)
        externalSelection = selection
    }

    /// The window the card renders before falling back to the first
    /// honestly available period.
    private var chosenPeriod: SensorHistoryPeriod? {
        externalSelection?.wrappedValue ?? selected
    }

    var body: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                header
                switch model.phase {
                case .loading: loadingState
                case .failed:  failedState
                case .loaded:
                    if let period = chosenPeriod ?? model.availablePeriods.first {
                        loadedContent(period)
                    } else {
                        emptyState
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: target.id) {
            // Sibling pickers can swap the presented sensor without
            // recreating this view — rebind the model to the new stream.
            if model.sensorId != target.id {
                model = SensorHistoryModel(sensorId: target.id)
                selected = nil
            }
            await model.load()
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.phase)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("sh_history_title")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            // Chips only in the EMBEDDED card — the sheet's page circle
            // hosts the same periods, so the header stays naked there.
            if externalSelection == nil, model.phase == .loaded,
               model.availablePeriods.count > 1 {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(model.availablePeriods) { period in
                        GlassFilterChip(label: period.title,
                                        isSelected: period == (chosenPeriod ?? model.availablePeriods.first)) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                                selected = period
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Loaded — chart + stats

    @ViewBuilder
    private func loadedContent(_ period: SensorHistoryPeriod) -> some View {
        let windowPoints = model.points(in: period)
        let values = windowPoints.compactMap(\.value)
        let unit = windowPoints.last?.unit ?? target.unit

        chart(windowPoints, period: period, unit: unit)

        if let latest = windowPoints.last, let latestValue = latest.value,
           let minValue = values.min(), let maxValue = values.max() {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.lg) {
                stat(titleKey: "sh_history_latest",
                     value: Self.text(latestValue, unit: unit),
                     emphasized: true)
                stat(titleKey: "sh_history_min", value: Self.text(minValue, unit: unit))
                stat(titleKey: "sh_history_max", value: Self.text(maxValue, unit: unit))
                Spacer(minLength: 0)
                Text(latest.createdAt, format: .relative(presentation: .named))
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        if model.isTruncated {
            // The cap bit — say the window shows only the newest slice.
            Text("sh_history_partial \(IoTService.historyQueryLimit)")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func chart(_ windowPoints: [IoTHistoryPoint],
                       period: SensorHistoryPeriod,
                       unit: String) -> some View {
        let display = Self.downsampled(windowPoints)
        let now = Date()
        return Chart(display) { point in
            if let value = point.value {
                AreaMark(x: .value("time", point.createdAt),
                         y: .value("value", value))
                    .foregroundStyle(.linearGradient(
                        colors: [target.tint.opacity(0.30), target.tint.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("time", point.createdAt),
                         y: .value("value", value))
                    .foregroundStyle(target.tint)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                if display.count <= 48 {
                    PointMark(x: .value("time", point.createdAt),
                              y: .value("value", value))
                        .foregroundStyle(target.tint)
                        .symbolSize(display.count == 1 ? 90 : 28)
                }
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-period.duration)...now)
        .chartYAxis { AxisMarks(position: .trailing) }
        .frame(height: 150)
        .accessibilityElement()
        .accessibilityLabel(Text("sh_history_title"))
        .accessibilityValue(Text(verbatim: accessibilitySummary(windowPoints, unit: unit)))
    }

    /// "21.5 °C · min 19 °C · max 23 °C" — the chart's spoken summary.
    private func accessibilitySummary(_ windowPoints: [IoTHistoryPoint], unit: String) -> String {
        let values = windowPoints.compactMap(\.value)
        guard let latest = values.last, let minV = values.min(), let maxV = values.max() else { return "" }
        return "\(Self.text(latest, unit: unit)) · \(String(localized: "sh_history_min")) \(Self.text(minV, unit: unit)) · \(String(localized: "sh_history_max")) \(Self.text(maxV, unit: unit))"
    }

    private func stat(titleKey: LocalizedStringKey, value: String,
                      emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titleKey)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(AppFont.scaled(emphasized ? 15 : 13, weight: .semibold))
                .foregroundStyle(emphasized ? AnyShapeStyle(target.tint) : AnyShapeStyle(.primary))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Honest loading / empty / failed states

    private var loadingState: some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("sh_history_loading")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("sh_history_empty_title")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
            Text("sh_history_empty_caption")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    }

    private var failedState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("sh_history_failed")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            Button {
                HapticFeedback.impact(.light)
                Task { await model.load() }
            } label: {
                Label("sh_history_retry", systemImage: "arrow.clockwise")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    }

    // MARK: Helpers

    /// "21,5 °C" — locale-aware, at most one decimal, the app's reading style.
    private static func text(_ value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        guard !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }

    /// Keeps the render cheap on dense webhook streams: over ~400 points
    /// the chart draws one point per time bucket (the bucket's last real
    /// measurement — never an average, so every drawn point is a genuine
    /// reading). Stats above always use the full window.
    private static func downsampled(_ input: [IoTHistoryPoint]) -> [IoTHistoryPoint] {
        let maxPoints = 400
        guard input.count > maxPoints else { return input }
        let stride = Double(input.count) / Double(maxPoints)
        var out: [IoTHistoryPoint] = []
        out.reserveCapacity(maxPoints + 1)
        var next = 0.0
        for (index, point) in input.enumerated() {
            if Double(index) >= next {
                out.append(point)
                next += stride
            }
        }
        if let last = input.last, out.last?.id != last.id { out.append(last) }
        return out
    }
}

// MARK: Sheet — the standalone presentation (space page tiles)

struct SensorHistorySheet: View {
    let target: SensorHistoryTarget

    @Environment(\.dismiss) private var dismiss
    /// Page-owned model + selection: the header's ONE filter circle reads
    /// the honest available periods from the same model the card renders
    /// (one-circle law — the period row is this page's range selector).
    @State private var model: SensorHistoryModel
    @State private var selectedPeriod: SensorHistoryPeriod? = nil

    init(target: SensorHistoryTarget) {
        self.target = target
        _model = State(initialValue: SensorHistoryModel(sensorId: target.id))
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(spacing: AppSpacing.sm) {
                        Button {
                            HapticFeedback.impact(.light)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .glassCircle()
                        .accessibilityLabel(Text("sh_close"))
                        Spacer(minLength: 0)
                        // The circle exists only when >1 window honestly
                        // holds data — the chips' exact contract. A period
                        // re-frames the chart, it doesn't narrow a list, so
                        // it never claims the "filtered" accent dot.
                        if model.phase == .loaded, model.availablePeriods.count > 1 {
                            GlassFilterButton(standaloneSize: 36) {
                                GlassFilterSection(
                                    title: "Period",
                                    options: model.availablePeriods.map {
                                        GlassPickerOption(value: $0, title: $0.title)
                                    },
                                    selection: Binding(
                                        get: { selectedPeriod ?? model.availablePeriods.first ?? .day },
                                        set: { selectedPeriod = $0 }))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("sh_history_title")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(verbatim: target.name)
                            .font(AppFont.scaled(26, weight: .light))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .combine)

                    SensorHistorySection(target: target, model: model,
                                         selection: $selectedPeriod)
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
