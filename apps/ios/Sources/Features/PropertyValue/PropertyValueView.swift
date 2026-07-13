import SwiftUI
import Charts
import UserNotifications

// MARK: - PropertyValueView ("Valoarea proprietății")
//
// The dedicated value page: KPI hero (current value, delta vs the previous
// evaluation, delta vs the purchase price when the history holds one, value
// per m² from the property's real area), the evolution line chart with a
// period filter that only offers periods that actually contain data, the
// typed-source history with per-entry deltas and swipe-to-delete, and the
// yearly revaluation reminder.
//
// Honesty notes:
//   • Mixed-currency histories are converted to the preferred currency
//     through CurrencyService's live BNR/ECB rates before any delta or chart
//     point is computed; single-currency histories display raw, unconverted.
//   • Swipe-EDIT is absent: PropertyValueService (read-only Services layer)
//     has no update method — a disabled or fake control would break the
//     honesty law. See the task report for the one-liner it needs.

struct PropertyValueView: View {
    /// The property whose history this page shows; nil → the active property.
    var propertyId: UUID? = nil

    @Environment(PropertyValueService.self) private var propertyValueService
    @Environment(PropertyService.self) private var propertyService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    @State private var showAdd = false
    @State private var period: ValuePeriod = .all
    @State private var remindAnnually = false

    // MARK: Data

    private var targetPropertyId: UUID? { propertyId ?? propertyService.primary?.id }

    private var property: PropertyModel? {
        guard let id = targetPropertyId else { return nil }
        return propertyService.properties.first { $0.id == id }
    }

    /// Oldest → newest; deltas and the chart read left to right.
    private var chronological: [PropertyValueEntry] {
        propertyValueService.sortedEntries.reversed()
    }

    /// One currency for every derived number. When the whole history shares
    /// a currency it is used as-is; mixed histories convert to the preferred
    /// currency so deltas never subtract EUR from RON.
    private var displayCurrency: String {
        let codes = Set(chronological.map(\.currency))
        if codes.count == 1, let only = codes.first { return only }
        return appSettings.preferredCurrency
    }

    private var isMixedCurrency: Bool { Set(chronological.map(\.currency)).count > 1 }

    private func displayAmount(_ entry: PropertyValueEntry) -> Double {
        isMixedCurrency
            ? currencyService.convert(entry.valueAmount, from: entry.currency, to: displayCurrency)
            : entry.valueAmount
    }

    private func money(_ amount: Double) -> String {
        CurrencyService.money(amount, code: displayCurrency, whole: true)
    }

    private var latest: PropertyValueEntry? { chronological.last }
    private var previous: PropertyValueEntry? {
        chronological.count >= 2 ? chronological[chronological.count - 2] : nil
    }

    /// The purchase-price entry seeded by the property form (typed source),
    /// if the history holds one that isn't also the latest entry.
    private var purchaseEntry: PropertyValueEntry? {
        guard let entry = chronological.first(where: { $0.typedSource == .purchase }),
              entry.id != latest?.id else { return nil }
        return entry
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if propertyValueService.entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Property Value")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add Value Entry")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPropertyValueSheet(propertyId: targetPropertyId)
                .environment(propertyValueService)
                .environment(propertyService)
                .environment(appSettings)
        }
        .task {
            if let id = targetPropertyId {
                await propertyValueService.load(propertyId: id)
                remindAnnually = PropertyRevaluationReminder.isEnabled(for: id)
            }
        }
        .onChange(of: propertyValueService.entries.count) {
            // A new evaluation re-anchors the yearly reminder to its date.
            guard remindAnnually, let id = targetPropertyId else { return }
            Task { await armReminder(true, propertyId: id) }
        }
    }

    // MARK: - Content (a List so history rows get real swipe actions)

    private var content: some View {
        List {
            Group {
                heroCard
                if chartEntries(for: effectivePeriod).count >= 2 {
                    chartCard
                }
                reminderCard
                historyHeader
                ForEach(propertyValueService.sortedEntries) { entry in
                    historyRow(entry)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                HapticFeedback.warning()
                                Task { await propertyValueService.delete(entry) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                Spacer(minLength: 90)
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: AppSpacing.xl,
                                      bottom: 6, trailing: AppSpacing.xl))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            if let id = targetPropertyId {
                await propertyValueService.load(propertyId: id)
            }
        }
    }

    // MARK: - Hero (current value + KPIs)

    private var heroCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Value")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .tracking(0.3)
                        if let latest {
                            Text(verbatim: money(displayAmount(latest)))
                                .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer()
                    Image(systemName: "house.fill")
                        .font(AppFont.scaled(24))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .glassRoundedRect(AppRadius.lg)
                }

                if let latest {
                    VStack(spacing: 0) {
                        if let previous {
                            kpiDeltaRow(label: "prop_value_kpi_vs_prev",
                                        from: displayAmount(previous),
                                        to: displayAmount(latest))
                        }
                        if let purchaseEntry {
                            kpiDivider
                            kpiDeltaRow(label: "prop_value_kpi_vs_purchase",
                                        from: displayAmount(purchaseEntry),
                                        to: displayAmount(latest))
                        }
                        if let size = property?.sizeSqm, size > 0 {
                            if previous != nil || purchaseEntry != nil { kpiDivider }
                            kpiRow(label: "prop_value_kpi_per_sqm",
                                   value: Text(verbatim: money(displayAmount(latest) / size) + "/m²"),
                                   tint: .primary)
                        }
                    }
                }
            }
        }
    }

    private func kpiDeltaRow(label: LocalizedStringKey, from: Double, to: Double) -> some View {
        let delta = to - from
        let pct = from > 0 ? delta / from * 100 : 0
        let tint: Color = delta >= 0 ? .brandSuccess : .brandDanger
        return kpiRow(
            label: label,
            value: Text(verbatim: "\(delta >= 0 ? "+" : "−")\(money(abs(delta)))" +
                        String(format: " (%+.1f%%)", pct)),
            tint: tint,
            icon: delta >= 0 ? "arrow.up.right" : "arrow.down.right"
        )
    }

    private func kpiRow(label: LocalizedStringKey, value: Text,
                        tint: Color, icon: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(tint)
            }
            value
                .font(AppFont.footnoteEmphasis)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var kpiDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
    }

    // MARK: - Chart (evolution + period filter)

    private struct ChartPoint: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private func chartEntries(for period: ValuePeriod) -> [ChartPoint] {
        let cutoff = period.cutoff
        return chronological.compactMap { entry in
            guard let date = entry.enteredDate else { return nil }
            if let cutoff, date < cutoff { return nil }
            return ChartPoint(id: entry.id, date: date, value: displayAmount(entry))
        }
    }

    /// Only periods that hold ≥2 points AND differ from the full history are
    /// offered — a "1A" chip identical to "Tot" would be a dead control.
    private var availablePeriods: [ValuePeriod] {
        let all = chartEntries(for: .all)
        guard all.count >= 2 else { return [] }
        var result: [ValuePeriod] = []
        for p: ValuePeriod in [.year1, .year3] {
            let subset = chartEntries(for: p)
            if subset.count >= 2 && subset.count < all.count { result.append(p) }
        }
        result.append(.all)
        return result
    }

    private var effectivePeriod: ValuePeriod {
        availablePeriods.contains(period) ? period : .all
    }

    private var chartCard: some View {
        let points = chartEntries(for: effectivePeriod)
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Value Over Time")
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    if availablePeriods.count > 1 {
                        HStack(spacing: AppSpacing.xs) {
                            ForEach(availablePeriods) { p in
                                GlassFilterChip(label: p.label,
                                                isSelected: effectivePeriod == p) {
                                    withAnimation(.snappy(duration: 0.3)) { period = p }
                                }
                            }
                        }
                    }
                }

                Chart(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Color.brandPrimaryBlue.opacity(0.35), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Color.brandPrimaryBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(Color.brandPrimaryBlue)
                    .symbolSize(36)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine().foregroundStyle(Color.primary.opacity(AppOpacity.hairline))
                        AxisValueLabel()
                            .font(AppFont.scaled(9))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                .frame(height: 180)

                if isMixedCurrency {
                    Text(verbatim: String(format: String(localized: "prop_value_converted_note"),
                                          displayCurrency))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
    }

    // MARK: - Annual revaluation reminder

    private var reminderCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(AppFont.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.brandWarning)
                    .frame(width: 36, height: 36)
                    .glassRoundedRect(AppRadius.sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text("prop_value_remind_toggle")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("prop_value_remind_note")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { remindAnnually },
                    set: { newValue in
                        remindAnnually = newValue
                        guard let id = targetPropertyId else { return }
                        Task { await armReminder(newValue, propertyId: id) }
                    }
                ))
                .labelsHidden()
                .tint(Color.accentColor)
                .accessibilityLabel("prop_value_remind_toggle")
            }
        }
    }

    private func armReminder(_ enabled: Bool, propertyId: UUID) async {
        let granted = await PropertyRevaluationReminder.setEnabled(
            enabled,
            propertyId: propertyId,
            propertyName: property?.name ?? "",
            anchor: latest?.enteredDate ?? Date()
        )
        // The toggle reflects reality: denied permission snaps it back off.
        if remindAnnually != granted { remindAnnually = granted }
    }

    // MARK: - History

    private var historyHeader: some View {
        Text("HISTORY")
            .font(AppFont.label)
            .foregroundStyle(.secondary)
            .padding(.top, AppSpacing.sm)
            .padding(.leading, AppSpacing.xs)
    }

    /// Delta vs the chronologically previous entry, in display currency.
    private func rowDelta(for entry: PropertyValueEntry) -> Double? {
        guard let idx = chronological.firstIndex(where: { $0.id == entry.id }),
              idx > 0 else { return nil }
        let prev = displayAmount(chronological[idx - 1])
        guard prev > 0 else { return nil }
        return (displayAmount(entry) - prev) / prev * 100
    }

    private func historyRow(_ entry: PropertyValueEntry) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: entry.sourceIcon)
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .glassRoundedRect(AppRadius.sm)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: CurrencyService.money(entry.valueAmount,
                                                             code: entry.currency,
                                                             whole: true))
                            .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        if let pct = rowDelta(for: entry) {
                            HStack(spacing: 2) {
                                Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text(verbatim: String(format: "%+.1f%%", pct))
                            }
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(pct >= 0 ? Color.brandSuccess : Color.brandDanger)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        if let date = entry.enteredDate {
                            Text(verbatim: AppDate.monthDayYear.string(from: date))
                        }
                        if let source = entry.sourceDisplay {
                            Text(verbatim: "·").foregroundStyle(Color.primary.opacity(0.2))
                            Text(verbatim: source).lineLimit(1)
                        }
                    }
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(verbatim: notes)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .lineLimit(3)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(AppFont.scaled(52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Track your property value")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            Text("Log manual estimates and bank appraisals to see how your property value changes over time.")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add First Entry", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Chart period

private enum ValuePeriod: Identifiable, Equatable {
    case year1, year3, all

    var id: String { label }

    var label: String {
        switch self {
        case .year1: return String(localized: "prop_value_period_1y")
        case .year3: return String(localized: "prop_value_period_3y")
        case .all:   return String(localized: "prop_value_period_all")
        }
    }

    /// Entries on/after this date belong to the period; nil → everything.
    var cutoff: Date? {
        switch self {
        case .year1: return Calendar.current.date(byAdding: .year, value: -1, to: Date())
        case .year3: return Calendar.current.date(byAdding: .year, value: -3, to: Date())
        case .all:   return nil
        }
    }
}

// MARK: - Yearly revaluation reminder
//
// A repeating calendar-triggered local notification on the anniversary of
// the last evaluation, following NotificationScheduler's monthly-recap
// pattern (one repeating trigger, namespaced identifier, permission checked
// before every arm). Lives here because Services is read-only; the logic is
// self-contained and per-property.
enum PropertyRevaluationReminder {
    private static func prefKey(_ propertyId: UUID) -> String {
        "prvio.value.revalRemind.\(propertyId.uuidString)"
    }
    private static func requestId(_ propertyId: UUID) -> String {
        "property.value.reval.\(propertyId.uuidString)"
    }

    static func isEnabled(for propertyId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: prefKey(propertyId))
    }

    /// Arms or disarms the yearly reminder. Returns the state that actually
    /// holds afterwards — false when notification permission was denied.
    @MainActor
    static func setEnabled(_ enabled: Bool, propertyId: UUID,
                           propertyName: String, anchor: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let id = requestId(propertyId)

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            UserDefaults.standard.set(false, forKey: prefKey(propertyId))
            return false
        }

        let settings = await center.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            authorized = (try? await center.requestAuthorization(
                options: [.alert, .sound, .badge])) ?? false
        }
        guard authorized else {
            UserDefaults.standard.set(false, forKey: prefKey(propertyId))
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "prop_value_notif_title")
        content.body = propertyName.isEmpty
            ? String(localized: "prop_value_notif_body_generic")
            : String(format: String(localized: "prop_value_notif_body"), propertyName)
        content.sound = .default

        // The anniversary of the last evaluation, 09:00, repeating yearly.
        var comps = Calendar.current.dateComponents([.month, .day], from: anchor)
        comps.hour = 9
        comps.minute = 0

        center.removePendingNotificationRequests(withIdentifiers: [id])
        try? await center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
        UserDefaults.standard.set(true, forKey: prefKey(propertyId))
        return true
    }
}
