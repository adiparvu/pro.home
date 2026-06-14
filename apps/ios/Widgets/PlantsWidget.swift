import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Plants Widget

struct PlantsWidget: Widget {
    let kind = "PlantsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            PlantsWidgetView(entry: entry)
        }
        .configurationDisplayName("Plante")
        .description("Arată plantele care au nevoie de apă.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Small View

struct PlantsSmallView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
                if entry.snapshot.plantsNeedingWater > 0 {
                    Text("\(entry.snapshot.plantsNeedingWater)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.1))
                } else {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("PLANTE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.plantsNeedingWater > 0
                     ? "Nevoie de apă"
                     : "Toate udate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://plants"))
    }
}

// MARK: - Medium View

struct PlantsMediumView: View {
    let entry: PRVIOWidgetEntry

    var needsWater: [PlantCatalogEntry] {
        entry.plantCatalog.filter { $0.needsWatering }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("PLANTE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Spacer()
                if entry.snapshot.plantsNeedingWater > 0 {
                    Text("\(entry.snapshot.plantsNeedingWater) nevoie de apă")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.1))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            if needsWater.isEmpty {
                HStack(spacing: 8) {
                    Text("🌿")
                    Text("Toate plantele sunt udate!")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(needsWater, id: \.id) { plant in
                        HStack(spacing: 8) {
                            Text(plant.emoji)
                                .font(.system(size: 16))
                            Text(plant.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            let intent = {
                                var i = WaterPlantIntent()
                                i.plant = PlantEntity(id: plant.id, name: plant.name, emoji: plant.emoji)
                                return i
                            }()
                            Button(intent: intent) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://plants"))
    }
}

// MARK: - Dispatcher

struct PlantsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  PlantsSmallView(entry: entry)
        case .systemMedium: PlantsMediumView(entry: entry)
        default:            PlantsSmallView(entry: entry)
        }
    }
}
