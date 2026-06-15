import SwiftUI

// MARK: - Widget type catalogue

enum HomeWidgetType: String, CaseIterable, Identifiable {
    case tasks, finances, documents, family, healthScore, inventory, contractors, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks:       return "Tasks"
        case .finances:    return "Finances"
        case .documents:   return "Documents"
        case .family:      return "Family"
        case .healthScore: return "Health Score"
        case .inventory:   return "Inventory"
        case .contractors: return "Contractors"
        case .calendar:    return "Calendar"
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

    @State private var enabled: Set<HomeWidgetType> = Set(HomeWidgetType.load())

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageHeader(title: "Widgets", subtitle: "HOME")

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Text("Choose which widgets appear on the home screen. Drag to reorder.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)

                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(HomeWidgetType.allCases.enumerated()), id: \.element.id) { idx, type in
                                    Button {
                                        HapticFeedback.selection()
                                        if enabled.contains(type) {
                                            if enabled.count > 1 { enabled.remove(type) }
                                        } else {
                                            enabled.insert(type)
                                        }
                                    } label: {
                                        HStack(spacing: 14) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(type.color.opacity(0.16))
                                                    .frame(width: 36, height: 36)
                                                Image(systemName: type.icon)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(type.color)
                                            }
                                            Text(type.title)
                                                .font(.system(size: 15))
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: enabled.contains(type)
                                                  ? "checkmark.circle.fill"
                                                  : "circle")
                                                .font(.system(size: 22))
                                                .foregroundStyle(enabled.contains(type)
                                                                 ? Color.accentColor
                                                                 : Color.primary.opacity(0.22))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 13)
                                    }
                                    .buttonStyle(.plain)
                                    if idx < HomeWidgetType.allCases.count - 1 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.05))
                                            .frame(height: 0.5)
                                            .padding(.leading, 66)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HomeWidgetType.save(Array(enabled))
                        appSettings.objectWillChange.send()
                        HapticFeedback.success()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.accentColor)
                }
            }
        }
    }
}
