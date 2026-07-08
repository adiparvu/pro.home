import WidgetKit
import SwiftUI
import AppIntents

struct ShoppingWidget: Widget {
    let kind = "ShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            ShoppingWidgetView(entry: entry)
        }
        .configurationDisplayName("Shopping")
        .description("Shows your shopping list.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Small

struct ShoppingSmallView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cart.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                Spacer()
                Text("\(entry.snapshot.pendingSupplyCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("SHOPPING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.pendingSupplyCount > 0
                     ? LocalizedStringKey("\(entry.snapshot.pendingSupplyCount) items")
                     : LocalizedStringKey("Empty list"))
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://shopping"))
    }
}

// MARK: - Medium (interactive check-off)

struct ShoppingMediumView: View {
    let entry: PRVIOWidgetEntry

    private var pending: [SupplyCatalogEntry] {
        entry.supplyCatalog.filter { !$0.isCompleted }.prefix(3).map { $0 }
    }

    private func makeCheckIntent(_ item: SupplyCatalogEntry) -> CheckSupplyItemIntent {
        var i = CheckSupplyItemIntent()
        i.item = SupplyItemEntity(id: item.id, name: item.name)
        return i
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("SHOPPING")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "cart.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                }
                Spacer()
                if entry.snapshot.pendingSupplyCount > 0 {
                    Text(LocalizedStringKey("\(entry.snapshot.pendingSupplyCount) items"))
                        .font(AppFont.label)
                        .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            if pending.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Empty list")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pending, id: \.id) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "cart")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button(intent: makeCheckIntent(item)) {
                                Image(systemName: "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://shopping"))
    }
}

// MARK: - Dispatcher

struct ShoppingWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PRVIOWidgetEntry

    var body: some View {
        switch family {
        case .systemMedium: ShoppingMediumView(entry: entry)
        default:            ShoppingSmallView(entry: entry)
        }
    }
}
