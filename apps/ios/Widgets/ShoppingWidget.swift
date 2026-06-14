import WidgetKit
import SwiftUI

struct ShoppingWidget: Widget {
    let kind = "ShoppingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            ShoppingWidgetView(entry: entry)
        }
        .configurationDisplayName("Cumpărături")
        .description("Arată lista de cumpărături.")
        .supportedFamilies([.systemSmall])
    }
}

struct ShoppingWidgetView: View {
    let entry: PRVIOWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.35, green: 0.65, blue: 1.0))
                Spacer()
                Text("\(entry.snapshot.pendingSupplyCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text("CUMPĂRĂTURI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.pendingSupplyCount > 0
                     ? "\(entry.snapshot.pendingSupplyCount) articole"
                     : "Listă goală")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "prvio://shopping"))
    }
}
