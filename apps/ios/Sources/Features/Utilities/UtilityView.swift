import SwiftUI
import Charts

struct UtilityEntry: Identifiable, Codable {
    var id = UUID()
    var type: String      // "electricity" | "water" | "gas" | "internet" | "other"
    var amount: Double
    var month: String     // "yyyy-MM"
    var unit: String      // "kWh", "m³", "€"
    var consumption: Double
}

@MainActor
final class UtilityService: ObservableObject {
    @Published var entries: [UtilityEntry] = []
    private let key = "prvio.utilities"

    init() { load() }

    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UtilityEntry].self, from: d) {
            entries = decoded.sorted { $0.month > $1.month }
        }
    }

    func add(_ e: UtilityEntry) { entries.insert(e, at: 0); entries.sort { $0.month > $1.month }; save() }
    func delete(_ e: UtilityEntry) { entries.removeAll { $0.id == e.id }; save() }

    func entriesFor(_ type: String) -> [UtilityEntry] { entries.filter { $0.type == type }.sorted { $0.month < $1.month } }
    func lastSixMonths(_ type: String) -> [UtilityEntry] { Array(entriesFor(type).suffix(6)) }

    func totalFor(_ type: String) -> Double { entriesFor(type).map(\.amount).reduce(0, +) }
    func currentMonthEntry(_ type: String) -> UtilityEntry? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        let current = f.string(from: Date())
        return entriesFor(type).first { $0.month == current }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: key) }
    }
}

// MARK: - Main View

struct UtilityView: View {
    @StateObject private var service = UtilityService()
    @State private var showAdd = false
    @State private var selectedType = "electricity"

    let types: [(id: String, icon: String, color: Color, label: String, unit: String)] = [
        ("electricity", "bolt.fill",      .yellow,                                  "Electricity", "kWh"),
        ("water",       "drop.fill",      .blue,                                    "Water",       "m³"),
        ("gas",         "flame.fill",     .orange,                                  "Gas",         "m³"),
        ("internet",    "wifi",           Color(red: 0.3, green: 0.85, blue: 0.5), "Internet",    "Mbps"),
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
                                isSelected: selectedType == t.id
                            )
                            .onTapGesture {
                                HapticFeedback.selection()
                                withAnimation(.spring(response: 0.25)) { selectedType = t.id }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        let typeData = service.lastSixMonths(selectedType)
                        let current = types.first { $0.id == selectedType }

                        if typeData.count >= 2 {
                            chartCard(data: typeData, color: current?.color ?? .white, unit: current?.unit ?? "")
                        }

                        if !typeData.isEmpty {
                            totalsCard(data: service.entriesFor(selectedType), color: current?.color ?? .white)
                        }

                        if typeData.isEmpty {
                            emptyState(type: current)
                        } else {
                            ForEach(service.entriesFor(selectedType).reversed()) { entry in
                                UtilityEntryRow(entry: entry, color: current?.color ?? .white)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            service.delete(entry)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 110)
                }
            }
        }
        .navigationTitle("Utilities")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.utilities)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddUtilitySheet(defaultType: selectedType) { entry in service.add(entry) }
        }
    }

    private func chartCard(data: [UtilityEntry], color: Color, unit: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last \(data.count) months")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                Chart(data, id: \.id) { e in
                    BarMark(
                        x: .value("Month", String(e.month.suffix(2))),
                        y: .value("€", e.amount)
                    )
                    .foregroundStyle(color.opacity(0.75))
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        Text("€\(String(format: "%.0f", e.amount))")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                }
                .frame(height: 130)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.secondary) } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel().foregroundStyle(.secondary)
                }}
                HStack {
                    let avg = data.map(\.amount).reduce(0, +) / Double(data.count)
                    let totalConsumption = data.map(\.consumption).reduce(0, +)
                    Label("Avg €\(String(format: "%.0f", avg))/mo", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if totalConsumption > 0 {
                        Label("\(String(format: "%.0f", totalConsumption)) \(unit) total", systemImage: "sum")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func totalsCard(data: [UtilityEntry], color: Color) -> some View {
        GlassCard {
            HStack(spacing: 0) {
                statCell(title: "This Year", value: "€\(String(format: "%.0f", data.filter { $0.month.hasPrefix(currentYear) }.map(\.amount).reduce(0, +)))", color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "All Time", value: "€\(String(format: "%.0f", data.map(\.amount).reduce(0, +)))", color: color)
                Divider().background(Color.primary.opacity(0.08)).frame(height: 36)
                statCell(title: "Bills", value: "\(data.count)", color: color)
            }
        }
    }

    private func statCell(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            Text(title).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private var currentYear: String {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f.string(from: Date())
    }

    private func emptyState(type: (id: String, icon: String, color: Color, label: String, unit: String)?) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            Image(systemName: type?.icon ?? "bolt.fill")
                .font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No \(type?.label ?? "") bills yet")
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.45))
            Text("Tap + to add manually or scan an invoice to extract data automatically.")
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Summary Card

private struct UtilitySummaryCard: View {
    let type: (id: String, icon: String, color: Color, label: String, unit: String)
    let currentEntry: UtilityEntry?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : type.color)
                Text(type.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .black : .white)
            }
            if let entry = currentEntry {
                Text("€\(String(format: "%.2f", entry.amount))")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? .black : type.color)
                if entry.consumption > 0 {
                    Text("\(String(format: "%.0f", entry.consumption)) \(type.unit)")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .black.opacity(0.6) : Color.primary.opacity(0.4))
                }
            } else {
                Text("No data")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .black.opacity(0.5) : Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(isSelected ? type.color : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
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
    var displayMonth: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: entry.month) else { return entry.month }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"; return out.string(from: d)
    }
    var body: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayMonth)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    if entry.consumption > 0 {
                        Text("\(String(format: "%.0f", entry.consumption)) \(entry.unit)")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Text("€\(String(format: "%.2f", entry.amount))")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            }
        }
    }
}
