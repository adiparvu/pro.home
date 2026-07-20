import SwiftUI

// MARK: - The shareable year — rendered cards, never screenshots
//
// Two fixed-size cards rendered on-device with ImageRenderer: the numbers
// card (cover + headline stats) and the highlights card (the story's best
// moments). Only lines whose data exists are drawn — a highlight card with
// nothing to say is simply not rendered or attached.

// MARK: - Card 1 — cover + stats

struct YearShareCard: View {
    let year: Int
    let propertyName: String
    /// (value, label) rows, already formatted and localized by the caller.
    let stats: [(value: String, label: String)]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(AppFont.scaled(44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(verbatim: propertyName)
                    .font(AppFont.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    HStack {
                        Text(verbatim: stat.label)
                            .font(AppFont.scaled(14))
                            .foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text(verbatim: stat.value)
                            .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            Text(verbatim: "PRVIO")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 20)
        }
        .frame(width: 340, height: 460)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.28),
                                    Color(red: 0.05, green: 0.16, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Card 2 — story highlights

struct YearHighlightsCard: View {
    let year: Int
    let propertyName: String
    /// (icon, text) rows — the story's chapters, already localized.
    let highlights: [(icon: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(String(localized: "year_share_highlights"))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(AppFont.scaled(14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.10), in: Circle())
                        Text(verbatim: item.text)
                            .font(AppFont.scaled(14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer()

            HStack {
                Text(verbatim: propertyName)
                    .font(AppFont.scaled(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(verbatim: "PRVIO")
                    .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 26)
        .frame(width: 340, height: 460)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.25),
                                    Color(red: 0.16, green: 0.07, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Rendering

enum YearShareRenderer {
    /// Renders one card to a PNG in the temporary directory (stable name per
    /// year + slot so re-renders overwrite instead of accumulating).
    @MainActor
    static func render<Card: View>(_ card: Card, year: Int, slot: String) -> URL? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO-\(year)-\(slot).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }
}
