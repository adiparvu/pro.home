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
        VStack(spacing: family == .systemMedium ? 10 : 8) {
            glyph
            wordmark
        }
        .multilineTextAlignment(.center)
        // Center the badge both axes in every family; an explicit alignment so
        // the wordmark never settles to a corner regardless of family sizing.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        // The monogram stands on its own — no plate behind it.
        Image("BrandMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: family == .systemMedium ? 56 : 48,
                   height: family == .systemMedium ? 56 : 48)
            .foregroundStyle(.white)
    }

    private var wordmark: some View {
        Text("PRVIO")
            .font(AppFont.scaled(24, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.white)
    }

}
