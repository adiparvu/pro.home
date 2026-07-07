import WidgetKit
import SwiftUI

// MARK: - PRVIO brand widget
//
// A simple, premium home-screen shortcut: the PRVIO monogram and wordmark
// centered on black — the composition of a hardware badge, not a data
// widget. Tapping it opens the app.

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
        // Everything centered on black: logo above, wordmark and tagline
        // beneath, the composition sitting in the optical middle.
        VStack(spacing: family == .systemMedium ? 8 : 6) {
            glyph
            wordmark
                .padding(.top, 2)
            tagline
            if family == .systemMedium,
               let name = snapshot.propertyName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            // Near-black with a faint crown of light so the panel reads as a
            // material, not a hole in the wallpaper.
            ZStack {
                Color.black
                RadialGradient(colors: [.white.opacity(0.07), .clear],
                               center: .top, startRadius: 0, endRadius: 200)
            }
        }
    }

    private var glyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 46, height: 46)
            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(.white)
        }
    }

    private var wordmark: some View {
        Text("PRVIO")
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .tracking(2)
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
