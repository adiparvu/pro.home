import SwiftUI
import Charts

struct UtilityEntry: Identifiable, Codable {
    var id = UUID()
    var type: String      // "electricity" | "water" | "gas" | "internet" | "other"
    var amount: Double
    var month: String     // "yyyy-MM"
    var unit: String      // "kWh", "m3", "€"
    var consumption: Double  // optional numeric consumption
}

@MainActor
final class UtilityService: ObservableObject {
    @Published var entries: [UtilityEntry] = []
    private let key = "prvhouse.utilities"

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

    private func save() {
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct UtilityView: View {
    @StateObject private var service = UtilityService()
    @State private var showAdd = false
    @State private var selectedType = "electricity"

    private let types: [(id: String, icon: String, color: Color, label: String)] = [
        ("electricity", "bolt.fill",      .yellow,                                    "Electricity"),
        ("water",       "drop.fill",      .blue,                                      "Water"),
        ("gas",         "flame.fill",     .orange,                                    "Gas"),
        ("internet",    "wifi",           Color(red: 0.3, green: 0.85, blue: 0.5),   "Internet"),
    ]

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(title: "Utilities",
                           trailing: AnyView(
                            Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(.white)
                            }
                           ))
                    .padding(.bottom, 12)

                // Type selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(types, id: \.id) { t in
                            Button {
                                HapticFeedback.selection()
                                withAnimation(.spring(response: 0.25)) { selectedType = t.id }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: t.icon).font(.system(size: 12))
                                    Text(t.label).font(.system(size: 13, weight: selectedType == t.id ? .semibold : .regular))
                                }
                                .foregroundStyle(selectedType == t.id ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(selectedType == t.id ? .white : .white.opacity(0.08), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }.padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        let typeData = service.lastSixMonths(selectedType)
                        let current = types.first { $0.id == selectedType }

                        if typeData.count >= 2 {
                            chartCard(data: typeData, color: current?.color ?? .white)
                        }

                        if typeData.isEmpty {
                            VStack(spacing: 12) {
                                Spacer(minLength: 40)
                                Image(systemName: current?.icon ?? "bolt.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.18))
                                Text("No \(current?.label ?? "") bills yet").font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
                                Spacer(minLength: 40)
                            }
                        } else {
                            ForEach(typeData.reversed()) { entry in
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
        .navigationTitle("Utilities").navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAdd) {
            AddUtilitySheet(defaultType: selectedType) { entry in service.add(entry) }
        }
    }

    private func chartCard(data: [UtilityEntry], color: Color) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last \(data.count) months").font(.headline)
                Chart(data, id: \.id) { e in
                    BarMark(x: .value("Month", String(e.month.suffix(2))), y: .value("€", e.amount))
                        .foregroundStyle(color.opacity(0.7)).cornerRadius(5)
                }
                .frame(height: 120)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(.secondary) } }
                .chartYAxis { AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(.secondary)
                }}
                let avg = data.map(\.amount).reduce(0,+) / Double(data.count)
                Text("Avg: €\(String(format: "%.0f", avg)) / month").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

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
                    Text(displayMonth).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    if entry.consumption > 0 {
                        Text("\(String(format: "%.0f", entry.consumption)) \(entry.unit)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
                Text("€\(String(format: "%.2f", entry.amount))").font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            }
        }
    }
}

private struct AddUtilitySheet: View {
    let defaultType: String
    let onSave: (UtilityEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: String
    @State private var amount = ""
    @State private var consumption = ""
    @State private var month = Date()

    private let types = ["electricity", "water", "gas", "internet", "other"]
    private let units = ["electricity": "kWh", "water": "m³", "gas": "m³", "internet": "Mbps", "other": "units"]

    init(defaultType: String, onSave: @escaping (UtilityEntry) -> Void) {
        self.defaultType = defaultType; self.onSave = onSave
        _type = State(initialValue: defaultType)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    GlassCard {
                        HStack {
                            Text("Type").font(.system(size: 15)).foregroundStyle(.white)
                            Spacer()
                            Picker("", selection: $type) {
                                ForEach(types, id: \.self) { Text($0.capitalized).tag($0) }
                            }.tint(.white.opacity(0.5))
                        }
                    }
                    GlassCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Amount (€)").font(.system(size: 15)).foregroundStyle(.white)
                                Spacer()
                                TextField("0.00", text: $amount).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).tint(.blue).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                            }.padding(.vertical, 4)
                            Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5)
                            HStack {
                                Text("Consumption (\(units[type] ?? "units"))").font(.system(size: 15)).foregroundStyle(.white)
                                Spacer()
                                TextField("0", text: $consumption).font(.system(size: 16)).foregroundStyle(.white).tint(.blue).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                            }.padding(.vertical, 4)
                            Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5)
                            DatePicker("Month", selection: $month, displayedComponents: [.date]).font(.system(size: 15)).foregroundStyle(.white).tint(.blue)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            .navigationTitle("Add Bill").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                        let entry = UtilityEntry(type: type, amount: Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                                month: f.string(from: month), unit: units[type] ?? "units",
                                                consumption: Double(consumption.replacingOccurrences(of: ",", with: ".")) ?? 0)
                        onSave(entry); HapticFeedback.success(); dismiss()
                    }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue).disabled(amount.isEmpty)
                }
            }
        }
    }
}
