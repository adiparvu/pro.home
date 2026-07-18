import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Plants Widget

struct PlantsWidget: Widget {
    let kind = "PlantsWidget"

    var body: some WidgetConfiguration {
        // Configurable (Edit Widget): the medium list can include healthy
        // plants under the thirsty ones. Placed widgets migrate with the
        // intent's default, which reproduces the thirsty-only widget.
        AppIntentConfiguration(kind: kind, intent: PlantsWidgetConfigIntent.self,
                               provider: PlantsConfigProvider()) { entry in
            PlantsWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_plants_name", comment: ""))
        .description(NSLocalizedString("widget_plants_desc", comment: ""))
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
                    .font(AppFont.headline)
                    .foregroundStyle(.green)
                    .widgetAccentable()
                Spacer()
                if entry.snapshot.plantsNeedingWater > 0 {
                    Text("\(entry.snapshot.plantsNeedingWater)")
                        .font(AppFont.scaled(28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.1))
                        .widgetAccentable()
                } else {
                    Image(systemName: "drop.fill")
                        .font(AppFont.scaled(24))
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("PLANTS")
                    .font(AppFont.scaled(9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.plantsNeedingWater > 0
                     ? LocalizedStringKey("Needs water")
                     : LocalizedStringKey("All watered"))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .moodContainerBackground()
        .widgetURL(URL(string: "prvio://plants"))
    }
}

// MARK: - Medium View

struct PlantsMediumView: View {
    let entry: PRVIOWidgetEntry

    /// Thirsty plants first; with "show healthy plants too" configured, the
    /// rest of the garden fills the remaining rows.
    var shownPlants: [PlantCatalogEntry] {
        let thirsty = entry.plantCatalog.filter { $0.needsWatering }
        guard entry.plantsConfig?.includeHealthy == true else {
            return thirsty.prefix(3).map { $0 }
        }
        return (thirsty + entry.plantCatalog.filter { !$0.needsWatering }).prefix(3).map { $0 }
    }

    private func makeWaterIntent(id: UUID, name: String, emoji: String) -> WaterPlantIntent {
        var i = WaterPlantIntent()
        i.plant = PlantEntity(id: id, name: name, emoji: emoji)
        return i
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("PLANTS")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "leaf.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.green)
                        .widgetAccentable()
                }
                Spacer()
                if entry.snapshot.plantsNeedingWater > 0 {
                    Text(String(format: String(localized: "%d need water"), entry.snapshot.plantsNeedingWater))
                        .font(AppFont.label)
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.1))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            if shownPlants.isEmpty {
                HStack(spacing: 8) {
                    Text("🌿")
                    Text("All plants are watered!")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shownPlants, id: \.id) { plant in
                        HStack(spacing: 8) {
                            Text(plant.emoji)
                                .font(AppFont.scaled(16))
                            Text(plant.name)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if plant.needsWatering {
                                Button(intent: makeWaterIntent(id: plant.id, name: plant.name, emoji: plant.emoji)) {
                                    Image(systemName: "drop.fill")
                                        .font(AppFont.scaled(14))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(AppFont.scaled(14))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .moodContainerBackground()
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
