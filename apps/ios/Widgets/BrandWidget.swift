import WidgetKit
import SwiftUI

// MARK: - PRVIO brand widget
//
// A simple, premium home-screen shortcut: the PRVIO wordmark on the brand
// gradient. Tapping it opens the app. Requested as "one that's just the PRVIO
// name and opens the app."

struct BrandWidget: Widget {
    let kind = "BrandWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRVIOTimelineProvider()) { entry in
            BrandWidgetView(snapshot: entry.snapshot)
                .widgetURL(URL(string: "prvio://"))
        }
        .configurationDisplayName("PRVIO")
        .description(NSLocalizedString("widget_brand_desc", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BrandWidgetView: View {
    let snapshot: PRVIOWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.36, blue: 0.78),
                         Color(red: 0.42, green: 0.24, blue: 0.72)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            glyph
            Spacer(minLength: 6)
            wordmark
            tagline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            glyph
            VStack(alignment: .leading, spacing: 4) {
                wordmark
                tagline
                if let name = snapshot.propertyName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(4)
    }

    private var glyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.white.opacity(0.16))
                .frame(width: 52, height: 52)
            Image(systemName: "house.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var wordmark: some View {
        Text("PRVIO")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.white)
    }

    private var tagline: some View {
        Text(NSLocalizedString("widget_brand_tagline", comment: ""))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
