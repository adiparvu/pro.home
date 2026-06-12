import SwiftUI

struct InventoryItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var category: String
    var brand: String
    var model: String
    var serialNumber: String
    var purchaseDate: String
    var warrantyUntil: String
    var value: Double
    var notes: String

    var categoryIcon: String {
        switch category.lowercased() {
        case "appliances": return "washer.fill"
        case "hvac": return "thermometer.medium"
        case "electronics": return "tv.fill"
        case "furniture": return "sofa.fill"
        case "tools": return "wrench.and.screwdriver.fill"
        case "security": return "lock.shield.fill"
        default: return "cube.fill"
        }
    }

    var warrantyStatus: WarrantyStatus {
        guard !warrantyUntil.isEmpty else { return .none }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: warrantyUntil) else { return .none }
        let now = Date()
        if d < now { return .expired }
        let days = Calendar.current.dateComponents([.day], from: now, to: d).day ?? 0
        if days <= 30 { return .expiringSoon }
        return .valid
    }

    enum WarrantyStatus { case none, valid, expiringSoon, expired }
}

@MainActor
final class InventoryService: ObservableObject {
    @Published var items: [InventoryItem] = []
    private let key = "prvhouse.inventory"

    init() { load() }

    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([InventoryItem].self, from: d) {
            items = decoded
        }
    }

    func add(_ item: InventoryItem) { items.append(item); save() }
    func delete(_ item: InventoryItem) { items.removeAll { $0.id == item.id }; save() }
    func update(_ item: InventoryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; save() }
    }

    var totalValue: Double { items.reduce(0) { $0 + $1.value } }
    var warrantyExpiringItems: [InventoryItem] { items.filter { $0.warrantyStatus == .expiringSoon } }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct InventoryView: View {
    @StateObject private var service = InventoryService()
    @State private var showAdd = false
    @State private var selectedCategory: String? = nil

    private let categories = ["All", "Appliances", "HVAC", "Electronics", "Furniture", "Tools", "Security"]

    var filtered: [InventoryItem] {
        guard let cat = selectedCategory, cat != "All" else { return service.items }
        return service.items.filter { $0.category.lowercased() == cat.lowercased() }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(title: "Inventory",
                           trailing: AnyView(
                            Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(.white)
                            }
                           ))
                    .padding(.bottom, 12)

                if !service.items.isEmpty {
                    summaryBar.padding(.horizontal, 20).padding(.bottom, 12)
                    categoryFilter.padding(.bottom, 12)
                }

                if service.items.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(filtered) { item in
                                InventoryRow(item: item)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            service.delete(item)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 110)
                    }
                }
            }
        }
        .navigationTitle("Inventory").navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAdd) { AddInventorySheet { item in service.add(item) } }
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            GlassCard(padding: 12) {
                VStack(spacing: 4) {
                    Text("€\(Int(service.totalValue))").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("Total Value").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }.frame(maxWidth: .infinity)
            }
            GlassCard(padding: 12) {
                VStack(spacing: 4) {
                    Text("\(service.items.count)").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("Items").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }.frame(maxWidth: .infinity)
            }
            GlassCard(padding: 12) {
                VStack(spacing: 4) {
                    Text("\(service.warrantyExpiringItems.count)").font(.system(size: 16, weight: .bold)).foregroundStyle(service.warrantyExpiringItems.isEmpty ? .white : .orange)
                    Text("Expiring").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isAll = cat == "All"
                    let isSelected = isAll ? selectedCategory == nil : selectedCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.25)) { selectedCategory = isAll ? nil : cat }
                    } label: {
                        Text(cat).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(isSelected ? .white : .white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.18))
            Text("No inventory yet").font(.system(size: 17)).foregroundStyle(.white.opacity(0.5))
            Button("Add first item") { showAdd = true }.font(.system(size: 14)).foregroundStyle(.blue)
            Spacer()
        }
    }
}

private struct InventoryRow: View {
    let item: InventoryItem
    var warrantyColor: Color {
        switch item.warrantyStatus {
        case .valid: return Color(red: 0.3, green: 0.85, blue: 0.5)
        case .expiringSoon: return .orange
        case .expired: return .red
        case .none: return .white.opacity(0.3)
        }
    }
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: item.categoryIcon, color: .blue, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 6) {
                        if !item.brand.isEmpty {
                            Text(item.brand).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                            Text("·").foregroundStyle(.white.opacity(0.2))
                        }
                        Text(item.category.capitalized).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                    if item.warrantyStatus != .none {
                        Label(item.warrantyStatus == .valid ? "Warranty valid" : item.warrantyStatus == .expiringSoon ? "Warranty expiring" : "Warranty expired",
                              systemImage: item.warrantyStatus == .valid ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(warrantyColor)
                    }
                }
                Spacer()
                if item.value > 0 {
                    Text("€\(Int(item.value))").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

private struct AddInventorySheet: View {
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var category = "Appliances"
    @State private var brand = ""; @State private var model = ""
    @State private var serial = ""; @State private var purchaseDate = Date()
    @State private var warrantyDate = Date(); @State private var hasWarranty = false
    @State private var value = ""; @State private var notes = ""

    private let categories = ["Appliances", "HVAC", "Electronics", "Furniture", "Tools", "Security", "Other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        sectionCard {
                            fieldRow("tag.fill", "Item name", $name)
                            divider
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                                Text("Category").font(.system(size: 15)).foregroundStyle(.white)
                                Spacer()
                                Picker("", selection: $category) {
                                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                                }.tint(.white.opacity(0.5))
                            }.padding(.horizontal, 16).padding(.vertical, 10)
                            divider
                            fieldRow("building.2.fill", "Brand", $brand)
                            divider
                            fieldRow("number", "Model / Serial", $serial)
                            divider
                            fieldRow("eurosign.circle.fill", "Value (€)", $value, keyboard: .decimalPad)
                        }
                        sectionCard {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                                DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                                    .font(.system(size: 15)).foregroundStyle(.white).tint(.blue)
                            }.padding(.horizontal, 16).padding(.vertical, 8)
                            divider
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                                Text("Has Warranty").font(.system(size: 15)).foregroundStyle(.white)
                                Spacer()
                                Toggle("", isOn: $hasWarranty).tint(.blue).labelsHidden()
                            }.padding(.horizontal, 16).padding(.vertical, 10)
                            if hasWarranty {
                                divider
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.clock").font(.system(size: 14)).foregroundStyle(.orange).frame(width: 28)
                                    DatePicker("Warranty Until", selection: $warrantyDate, displayedComponents: .date)
                                        .font(.system(size: 15)).foregroundStyle(.white).tint(.blue)
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
                        let item = InventoryItem(
                            name: name, category: category, brand: brand, model: model,
                            serialNumber: serial,
                            purchaseDate: iso.string(from: purchaseDate),
                            warrantyUntil: hasWarranty ? iso.string(from: warrantyDate) : "",
                            value: Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0,
                            notes: notes
                        )
                        onSave(item)
                        HapticFeedback.success()
                        dismiss()
                    }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue).disabled(name.isEmpty)
                }
            }
        }
    }

    private func sectionCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }
    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
            TextField(placeholder, text: binding).font(.system(size: 15)).foregroundStyle(.white).tint(.blue).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}
