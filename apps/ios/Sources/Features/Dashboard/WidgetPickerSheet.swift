import SwiftUI

// MARK: - Home section order (drag-reorderable page sections)

enum HomeSectionType: String, CaseIterable, Identifiable {
    case healthCard = "healthCard"
    case statsStrip = "statsStrip"
    case widgets    = "widgets"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthCard: return String(localized: "Health Card")
        case .statsStrip: return String(localized: "Stats")
        case .widgets:    return String(localized: "Overview Widgets")
        }
    }

    var icon: String {
        switch self {
        case .healthCard: return "heart.fill"
        case .statsStrip: return "chart.bar.fill"
        case .widgets:    return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .healthCard: return .red
        case .statsStrip: return .blue
        case .widgets:    return .purple
        }
    }

    static let key = "prvio.homeSections"

    static func load() -> [HomeSectionType] {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return allCases }
        let saved = raw.split(separator: ",").compactMap { HomeSectionType(rawValue: String($0)) }
        let missing = allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    static func save(_ order: [HomeSectionType]) {
        UserDefaults.standard.set(order.map(\.rawValue).joined(separator: ","), forKey: key)
    }
}

// MARK: - Widget type catalogue

enum HomeWidgetType: String, CaseIterable, Identifiable {
    case tasks, finances, documents, family, healthScore, inventory,
         contractors, weather, plants, calendar

    var id: String { rawValue }

    var isFullWidth: Bool {
        self == .weather || self == .calendar
    }

    var title: String {
        switch self {
        case .tasks:       return String(localized: "Tasks")
        case .finances:    return String(localized: "Finances")
        case .documents:   return String(localized: "Documents")
        case .family:      return String(localized: "Family")
        case .healthScore: return String(localized: "Health Score")
        case .inventory:   return String(localized: "Inventory")
        case .contractors: return String(localized: "Contractors")
        case .weather:     return String(localized: "Weather")
        case .plants:      return String(localized: "Plants")
        case .calendar:    return String(localized: "Calendar")
        }
    }

    var icon: String {
        switch self {
        case .tasks:       return "checklist"
        case .finances:    return "creditcard.fill"
        case .documents:   return "doc.fill"
        case .family:      return "person.2.fill"
        case .healthScore: return "heart.fill"
        case .inventory:   return "shippingbox.fill"
        case .contractors: return "hammer.fill"
        case .weather:     return "cloud.sun.fill"
        case .plants:      return "leaf.fill"
        case .calendar:    return "calendar"
        }
    }

    var color: Color {
        switch self {
        case .tasks:       return .blue
        case .finances:    return Color(red: 0.3, green: 0.85, blue: 0.45)
        case .documents:   return Color(red: 0.55, green: 0.55, blue: 0.95)
        case .family:      return Color(red: 0.7, green: 0.45, blue: 0.95)
        case .healthScore: return .red
        case .inventory:   return .orange
        case .contractors: return Color(red: 0.9, green: 0.65, blue: 0.2)
        case .weather:     return Color(red: 0.2, green: 0.55, blue: 0.95)
        case .plants:      return Color(red: 0.25, green: 0.78, blue: 0.45)
        case .calendar:    return .teal
        }
    }

    static let defaultRaw = "tasks,finances,documents,family"
    static let key = "prvio.homeWidgets"

    static func load() -> [HomeWidgetType] {
        let raw = UserDefaults.standard.string(forKey: key) ?? defaultRaw
        return raw.split(separator: ",").compactMap { HomeWidgetType(rawValue: String($0)) }
    }

    static func save(_ types: [HomeWidgetType]) {
        UserDefaults.standard.set(types.map(\.rawValue).joined(separator: ","), forKey: key)
    }
}

// MARK: - Widget picker sheet

struct WidgetPickerSheet: View {
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var active: [HomeWidgetType] = HomeWidgetType.load()

    private var inactive: [HomeWidgetType] {
        HomeWidgetType.allCases.filter { !active.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { type in
                            widgetRow(type, isActive: true)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onMove { from, to in
                            active.move(fromOffsets: from, toOffset: to)
                        }
                        .onDelete { offsets in
                            guard active.count - offsets.count >= 1 else { return }
                            active.remove(atOffsets: offsets)
                        }
                    } header: {
                        Text("Active — trage pentru reordonare")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }

                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive) { type in
                            Button {
                                HapticFeedback.selection()
                                withAnimation(.spring(response: 0.35)) {
                                    active.append(type)
                                }
                            } label: {
                                widgetRow(type, isActive: false)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        Text("Disponibile")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(appBackground.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Widgeturi")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gata") {
                        HomeWidgetType.save(active)
                        appSettings.objectWillChange.send()
                        HapticFeedback.success()
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func widgetRow(_ type: HomeWidgetType, isActive: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(type.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: type.icon)
                    .font(AppFont.headline)
                    .foregroundStyle(type.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type.title)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                if type.isFullWidth {
                    Text("Lățime completă")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
