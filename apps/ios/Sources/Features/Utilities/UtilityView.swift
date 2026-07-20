import SwiftUI
import Charts
import Observation

struct UtilityEntry: Identifiable, Codable {
    var id: UUID
    var appCategory: String   // "electricity" | "water" | "gas" | "internet" | "other"
    var meterType: String     // DB enum: electricity / gas / water / solar / district_heating / other
    var cost: Double?
    var readingDate: String   // "yyyy-MM-dd" (stored as first of month)
    var readingValue: Double
    var unit: String          // "kWh", "m3", etc.

    enum CodingKeys: String, CodingKey {
        case id, unit, cost
        case appCategory  = "app_category"
        case meterType    = "meter_type"
        case readingDate  = "reading_date"
        case readingValue = "reading_value"
    }

    // Derived helpers matching the old API surface
    var type: String { appCategory }
    var amount: Double { cost ?? 0 }
    var month: String { String(readingDate.prefix(7)) }    // "yyyy-MM"
    var consumption: Double { readingValue }
}

struct NewUtilityEntry: Encodable {
    let propertyId: UUID
    let appCategory: String
    let meterType: String
    let readingDate: String
    let readingValue: Double
    let unit: String
    let cost: Double?
    enum CodingKeys: String, CodingKey {
        case unit, cost
        case propertyId   = "property_id"
        case appCategory  = "app_category"
        case meterType    = "meter_type"
        case readingDate  = "reading_date"
        case readingValue = "reading_value"
    }
}

@MainActor
@Observable
final class UtilityService {
    var entries: [UtilityEntry] = []
    private(set) var currentPropertyId: UUID?

    // MARK: Derived helpers

    func entriesFor(_ type: String) -> [UtilityEntry] {
        entries.filter { $0.appCategory == type }.sorted { $0.readingDate < $1.readingDate }
    }
    func lastSixMonths(_ type: String) -> [UtilityEntry] { Array(entriesFor(type).suffix(6)) }
    func currentMonthEntry(_ type: String) -> UtilityEntry? {
        let current = AppDate.monthKey.string(from: Date())
        return entriesFor(type).first { $0.month == current }
    }

    // MARK: Supabase CRUD

    func load(propertyId: UUID) async {
        currentPropertyId = propertyId
        do {
            entries = try await supabase
                .from("energy_readings")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("reading_date", ascending: false)
                .execute()
                .value
        } catch {
            #if DEBUG
            debugLog("UtilityService.load error:", error)
            #endif
        }
    }

    func add(_ new: NewUtilityEntry) async {
        do {
            let result: UtilityEntry = try await supabase
                .from("energy_readings")
                .insert(new)
                .select()
                .single()
                .execute()
                .value
            entries.insert(result, at: 0)
            entries.sort { $0.readingDate > $1.readingDate }
        } catch {
            #if DEBUG
            debugLog("UtilityService.add error:", error)
            #endif
        }
    }

    func delete(_ e: UtilityEntry) async {
        do {
            try await supabase
                .from("energy_readings")
                .delete()
                .eq("id", value: e.id.uuidString)
                .execute()
            entries.removeAll { $0.id == e.id }
        } catch {
            #if DEBUG
            debugLog("UtilityService.delete error:", error)
            #endif
        }
    }

    // Maps app type string to DB meter_type enum value
    static func meterType(for appType: String) -> String {
        switch appType {
        case "electricity": return "electricity"
        case "water":       return "water"
        case "gas":         return "gas"
        case "solar":       return "solar"
        default:            return "other"
        }
    }

    // Maps app unit string to DB energy_unit enum value
    static func dbUnit(for appUnit: String) -> String {
        switch appUnit {
        case "kWh":  return "kWh"
        case "m³", "m3": return "m3"
        case "L":    return "L"
        case "GJ":   return "GJ"
        default:     return "other"
        }
    }
}

// MARK: - Main View

struct UtilityView: View {
    @State private var service = UtilityService()
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @State private var showAdd = false
    @State private var selectedType = "electricity"

    /// Bills display in the household's preferred currency — the "€" that
    /// used to be hardcoded showed euros over RON amounts.
    private var currencyCode: String { appSettings.preferredCurrency }

    let types: [(id: String, icon: String, color: Color, label: String, unit: String)] = [
        ("electricity", "bolt.fill",      .yellow,                                  String(localized: "Electricity"), "kWh"),
        ("water",       "drop.fill",      .blue,                                    String(localized: "Water"),       "m³"),
        ("gas",         "flame.fill",     .orange,                                  String(localized: "Gas"),         "m³"),
        ("internet",    "wifi",           Color.brandSuccess, String(localized: "Internet"),    "Mbps"),
    ]

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(types, id: \.id) { t in
                            UtilitySummaryCard(
                                type: t,
                                currentEntry: service.currentMonthEntry(t.id),
                                isSelected: selectedType == t.id,
                                code: currencyCode
                            )
                            .onTapGesture {
                                HapticFeedback.selection()
                                withAnimation(.spring(response: 0.25)) { selectedType = t.id }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                }
                .padding(.bottom, AppSpacing.lg)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // One filter+sort per render — entriesFor() used to
                        // run three times per body evaluation.
                        let allEntries = service.entriesFor(selectedType)
                        let typeData = Array(allEntries.suffix(6))
                        let current = types.first { $0.id == selectedType }

                        if typeData.count >= 2 {
                            chartCard(data: typeData, color: current?.color ?? .white, unit: current?.unit ?? "")
                        }

                        if !typeData.isEmpty {
                            totalsCard(data: allEntries, color: current?.color ?? .white)
                        }

                        if typeData.isEmpty {
                            emptyState(type: current)
                        } else {
                            ForEach(allEntries.reversed()) { entry in
                                UtilityEntryRow(entry: entry, color: current?.color ?? .white, code: currencyCode)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await service.delete(entry) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.bottom, 110)
                }
                .refreshable {
                    if let pid = propertyService.primary?.id {
                        await service.load(propertyId: pid)
                    }
                }
            }
        }
        .navigationTitle("Utilities")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.utilities)
        .task(id: propertyService.primary?.id) {
            if let pid = propertyService.primary?.id {
                await service.load(propertyId: pid)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add utility bill")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddUtilitySheet(defaultType: selectedType, propertyId: service.currentPropertyId) { entry in
                Task { await service.add(entry) }
            }
        }
    }

    private func chartCard(data: [UtilityEntry], color: Color, unit: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last \(data.count) months")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Spacer()
                    monthOverMonth(data)
                }
                Chart(data, id: \.id) { e in
                    BarMark(
                        x: .value("Month", String(e.month.suffix(2))),
                        y: .value("Amount", e.amount)
                    )
                    .foregroundStyle(color.opacity(0.75))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text(verbatim: CurrencyService.money(e.amount, code: currencyCode, whole: true))
                            .font(AppFont.scaled(9))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                }
                .frame(height: 130)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.secondary) } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(AppOpacity.hairline))
                    AxisValueLabel().foregroundStyle(.secondary)
                }}
                HStack {
                    let avg = data.map(\.amount).reduce(0, +) / Double(data.count)
                    let totalConsumption = data.map(\.consumption).reduce(0, +)
                    Label(String(format: String(localized: "util_avg %@"),
                                 CurrencyService.money(avg, code: currencyCode, whole: true)),
                          systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if totalConsumption > 0 {
                        Label(String(format: String(localized: "util_total_consumption %@ %@"),
                                     String(format: "%.0f", totalConsumption), unit),
                              systemImage: "sum")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Latest bill vs. the one before — the number that says whether this
    /// utility is getting more expensive. Only shown for real changes (≥1%).
    @ViewBuilder
    private func monthOverMonth(_ data: [UtilityEntry]) -> some View {
        if data.count >= 2 {
            let last = data[data.count - 1].amount
            let previous = data[data.count - 2].amount
            if previous > 0 {
                let pct = Int(((last - previous) / previous * 100).rounded())
                if pct != 0 {
                    let rising = pct > 0
                    Label(String(format: String(localized: rising ? "util_mom_up %lld" : "util_mom_down %lld"),
                                 abs(pct)),
                          systemImage: rising ? "arrow.up.right" : "arrow.down.right")
                        .font(AppFont.label)
                        .foregroundStyle(rising ? Color.orange : Color.brandSuccess)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background((rising ? Color.orange : Color.brandSuccess).opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private func totalsCard(data: [UtilityEntry], color: Color) -> some View {
        GlassCard {
            HStack(spacing: 0) {
                statCell(title: "This Year",
                         value: CurrencyService.money(
                            data.filter { $0.month.hasPrefix(currentYear) }.map(\.amount).reduce(0, +),
                            code: currencyCode, whole: true),
                         color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "All Time",
                         value: CurrencyService.money(data.map(\.amount).reduce(0, +),
                                                      code: currencyCode, whole: true),
                         color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "Bills", value: "\(data.count)", color: color)
            }
        }
    }

    private func statCell(title: LocalizedStringKey, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(AppFont.scaled(16, weight: .bold)).foregroundStyle(color)
            Text(title).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var currentYear: String {
        AppDate.yearKey.string(from: Date())
    }

    private func emptyState(type: (id: String, icon: String, color: Color, label: String, unit: String)?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            EmptyStateView(
                icon: type?.icon ?? "bolt.fill",
                title: "No \(type?.label ?? "") bills yet",
                message: "Tap + to add manually or scan an invoice to extract data automatically."
            )
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Summary Card

private struct UtilitySummaryCard: View {
    let type: (id: String, icon: String, color: Color, label: String, unit: String)
    let currentEntry: UtilityEntry?
    let isSelected: Bool
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(isSelected ? .black : type.color)
                Text(type.label)
                    .font(AppFont.captionStrong)
                    // .white was hardcoded — invisible on the light theme.
                    .foregroundStyle(isSelected ? Color.black : Color.primary)
            }
            if let entry = currentEntry {
                Text(verbatim: CurrencyService.money(entry.amount, code: code, whole: false))
                    .font(AppFont.scaled(17, weight: .bold))
                    .foregroundStyle(isSelected ? .black : type.color)
                if entry.consumption > 0 {
                    Text("\(String(format: "%.0f", entry.consumption)) \(type.unit)")
                        .font(AppFont.scaled(10))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.primary.opacity(0.4))
                }
            } else {
                Text("No data")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(isSelected ? .black.opacity(0.5) : Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
        .background(isSelected ? type.color : Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? .clear : type.color.opacity(0.25), lineWidth: 1)
        )
        .animation(.spring(response: 0.2), value: isSelected)
    }
}

// MARK: - Entry Row

private struct UtilityEntryRow: View {
    let entry: UtilityEntry
    let color: Color
    let code: String

    // Built once — a fresh DateFormatter per row per render is real cost
    // on a long bill history.
    private static let monthDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var displayMonth: String {
        guard let d = AppDate.monthKey.date(from: entry.month) else { return entry.month }
        return Self.monthDisplay.string(from: d)
    }

    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayMonth)
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    if entry.consumption > 0 {
                        Text("\(String(format: "%.0f", entry.consumption)) \(entry.unit)")
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Text(verbatim: CurrencyService.money(entry.amount, code: code, whole: false))
                    .font(AppFont.scaled(16, weight: .bold)).foregroundStyle(color)
            }
        }
    }
}
