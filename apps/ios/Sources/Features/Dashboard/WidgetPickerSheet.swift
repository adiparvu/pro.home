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
        // Dashboard redesign: health lives in the hero status pill and the
        // counters became the "Today" card, so only the widgets section
        // remains on the page (saved orders from older builds still decode,
        // the retired sections just render nothing).
        guard let raw = UserDefaults.standard.string(forKey: key) else { return [.widgets] }
        let saved = raw.split(separator: ",").compactMap { HomeSectionType(rawValue: String($0)) }
        let missing = allCases.filter { !saved.contains($0) }
        return (saved + missing).filter { $0 == .widgets }
    }

    static func save(_ order: [HomeSectionType]) {
        UserDefaults.standard.set(order.map(\.rawValue).joined(separator: ","), forKey: key)
    }
}

// MARK: - Widget type catalogue

enum HomeWidgetType: String, CaseIterable, Identifiable {
    case tasks, finances, documents, family, healthScore, inventory,
         contractors, weather, plants, calendar, deliveries, shopping, journal,
         briefing, presence, budget,
         pantry, insights, propertyValue, seasonal, warranties, houseFeed,
         whoHome

    var id: String { rawValue }

    /// The size a widget arrives in — every widget can be resized afterwards.
    var defaultSize: HomeWidgetSize {
        switch self {
        case .weather, .calendar, .briefing, .insights, .houseFeed: return .full
        default: return .half
        }
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
        case .deliveries:  return String(localized: "Deliveries")
        case .shopping:    return String(localized: "Shopping list")
        case .journal:     return String(localized: "Photo Journal")
        case .briefing:    return String(localized: "House Briefing")
        case .presence:    return String(localized: "Presence")
        case .budget:      return String(localized: "Budget")
        case .pantry:      return String(localized: "Pantry")
        case .insights:    return String(localized: "For you")
        case .propertyValue: return String(localized: "Property value")
        case .seasonal:    return String(localized: "Seasonal")
        case .warranties:  return String(localized: "Warranties")
        case .houseFeed:   return String(localized: "Today at home")
        case .whoHome:     return String(localized: "Who's home")
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
        case .deliveries:  return "shippingbox.and.arrow.backward.fill"
        case .shopping:    return "cart.fill"
        case .journal:     return "photo.stack.fill"
        case .briefing:    return "sparkles"
        case .presence:    return "person.2.wave.2.fill"
        case .budget:      return "chart.pie.fill"
        case .pantry:      return "basket.fill"
        case .insights:    return "lightbulb.fill"
        case .propertyValue: return "chart.line.uptrend.xyaxis"
        case .seasonal:    return "leaf.circle.fill"
        case .warranties:  return "checkmark.seal.fill"
        case .houseFeed:   return "clock.arrow.circlepath"
        case .whoHome:     return "location.fill.viewfinder"
        }
    }

    var color: Color {
        switch self {
        case .tasks:       return .blue
        case .finances:    return Color.brandSuccess
        case .documents:   return Color(red: 0.55, green: 0.55, blue: 0.95)
        case .family:      return Color(red: 0.7, green: 0.45, blue: 0.95)
        case .healthScore: return .red
        case .inventory:   return .orange
        case .contractors: return Color(red: 0.9, green: 0.65, blue: 0.2)
        case .weather:     return Color.brandPrimaryBlue
        case .plants:      return Color(red: 0.25, green: 0.78, blue: 0.45)
        case .calendar:    return .teal
        case .deliveries:  return Color.brandSkyBlue
        case .shopping:    return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .journal:     return Color.brandPurple
        case .briefing:    return Color.brandPurple
        case .presence:    return Color.brandSuccess
        case .budget:      return Color.brandWarning
        case .pantry:      return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .insights:    return Color.brandPrimaryBlue
        case .propertyValue: return Color.brandSuccess
        case .seasonal:    return Color(red: 0.25, green: 0.78, blue: 0.45)
        case .warranties:  return Color.brandSkyBlue
        case .houseFeed:   return Color.brandPrimaryBlue
        case .whoHome:     return Color.brandSkyBlue
        }
    }
}

// MARK: - Widget size

enum HomeWidgetSize: String, CaseIterable {
    case half, full

    var title: String {
        switch self {
        case .half: return String(localized: "Half width")
        case .full: return String(localized: "Full width")
        }
    }

    var icon: String {
        switch self {
        case .half: return "square.split.2x1"
        case .full: return "rectangle"
        }
    }

    var toggled: HomeWidgetSize { self == .half ? .full : .half }
}

// MARK: - Widget configuration (type + chosen size, persisted in order)

struct HomeWidgetConfig: Identifiable, Equatable {
    var type: HomeWidgetType
    var size: HomeWidgetSize

    var id: String { type.rawValue }

    static let key = "prvio.homeWidgets"
    private static let defaultRaw = "tasks,finances,documents,family"

    /// Persisted as "type:size,…". Entries saved before sizes existed have no
    /// ":size" suffix and fall back to the type's natural default.
    static func load() -> [HomeWidgetConfig] {
        let raw = UserDefaults.standard.string(forKey: key) ?? defaultRaw
        return raw.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let first = parts.first,
                  let type = HomeWidgetType(rawValue: String(first)) else { return nil }
            let size = parts.count > 1 ? HomeWidgetSize(rawValue: String(parts[1])) : nil
            return HomeWidgetConfig(type: type, size: size ?? type.defaultSize)
        }
    }

    static func save(_ configs: [HomeWidgetConfig]) {
        UserDefaults.standard.set(
            configs.map { "\($0.type.rawValue):\($0.size.rawValue)" }.joined(separator: ","),
            forKey: key
        )
    }
}

// MARK: - Widget picker sheet

struct WidgetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var active: [HomeWidgetConfig] = HomeWidgetConfig.load()

    private var inactive: [HomeWidgetType] {
        let activeTypes = Set(active.map(\.type))
        return HomeWidgetType.allCases.filter { !activeTypes.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !active.isEmpty {
                    Section {
                        ForEach(active) { config in
                            activeRow(config)
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
                        Text("Active — drag to reorder")
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
                                    active.append(HomeWidgetConfig(type: type, size: type.defaultSize))
                                }
                            } label: {
                                availableRow(type)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        Text("Available")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Widgets")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HomeWidgetConfig.save(active)
                        HapticFeedback.success()
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .sheetGround()
    }

    // Clear Liquid Glass badge — colour lives on the glyph, never on a tile.
    private func iconBadge(_ type: HomeWidgetType) -> some View {
        Image(systemName: type.icon)
            .font(AppFont.headline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(type.color)
            .frame(width: 40, height: 40)
            .mediaGlass(in: Circle())
    }

    /// Active row: title + current size caption, and a size toggle that flips
    /// the widget between half and full width.
    private func activeRow(_ config: HomeWidgetConfig) -> some View {
        HStack(spacing: 14) {
            iconBadge(config.type)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.type.title)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Text(config.size.title)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            Spacer()

            Button {
                HapticFeedback.selection()
                guard let idx = active.firstIndex(where: { $0.id == config.id }) else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    active[idx].size = active[idx].size.toggled
                }
            } label: {
                Image(systemName: config.size.icon)
                    .font(AppFont.body)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .mediaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Widget size"))
            .accessibilityValue(Text(verbatim: config.size.title))

            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.scaled(22))
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())
    }

    private func availableRow(_ type: HomeWidgetType) -> some View {
        HStack(spacing: 14) {
            iconBadge(type)

            Text(type.title)
                .font(AppFont.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "plus.circle")
                .font(AppFont.scaled(22))
                .foregroundStyle(Color.primary.opacity(0.3))
        }
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())
    }
}
