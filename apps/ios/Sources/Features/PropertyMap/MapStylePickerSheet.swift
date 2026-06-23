import SwiftUI

struct MapStylePickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    private let styles: [(id: String, title: String, subtitle: String)] = [
        ("hybrid",    "Hybrid",    "Satellite + Roads"),
        ("standard",  "Standard",  "Street Map"),
        ("satellite", "Satellite", "Imagery Only"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            Text("Map Style")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 16)

            HStack(spacing: 12) {
                ForEach(styles, id: \.id) { style in
                    StyleCard(
                        id: style.id,
                        title: style.title,
                        subtitle: style.subtitle,
                        isSelected: selected == style.id
                    ) {
                        selected = style.id
                        HapticFeedback.selection()
                        Task { try? await Task.sleep(for: .milliseconds(200)); dismiss() }
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(appBackground.ignoresSafeArea())
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.thinMaterial)
    }
}

private struct StyleCard: View {
    let id: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack {
                    Canvas { ctx, size in
                        switch id {
                        case "standard":  drawStandard(&ctx, size)
                        case "satellite": drawSatellite(&ctx, size)
                        default:          drawHybrid(&ctx, size)
                        }
                    }
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .background(Color.accentColor, in: Circle())
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineLimit(1)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Canvas draw helpers (ctx must be inout so mutating calls compile)

    private func drawHybrid(_ ctx: inout GraphicsContext, _ size: CGSize) {
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.17, green: 0.24, blue: 0.19),
                    Color(red: 0.13, green: 0.20, blue: 0.22)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )
        for rect in [
            CGRect(x: 4,  y: 6,  width: 28, height: 22),
            CGRect(x: 58, y: 14, width: 40, height: 28),
            CGRect(x: 14, y: 54, width: 22, height: 30),
            CGRect(x: 80, y: 52, width: 30, height: 26),
        ] {
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 4),
                with: .color(Color(red: 0.20, green: 0.38, blue: 0.22).opacity(0.75))
            )
        }
        drawRoads(&ctx, size, Color(red: 0.85, green: 0.78, blue: 0.60))
    }

    private func drawStandard(_ ctx: inout GraphicsContext, _ size: CGSize) {
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0.94, green: 0.93, blue: 0.90))
        )
        for rect in [
            CGRect(x: 6,  y: 8,  width: 30, height: 24),
            CGRect(x: 54, y: 6,  width: 38, height: 20),
            CGRect(x: 6,  y: 52, width: 24, height: 30),
            CGRect(x: 76, y: 44, width: 34, height: 36),
            CGRect(x: 40, y: 38, width: 28, height: 38),
        ] {
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 2),
                with: .color(Color(red: 0.84, green: 0.83, blue: 0.79))
            )
        }
        ctx.fill(
            Path(roundedRect: CGRect(x: 54, y: 48, width: 18, height: 18), cornerRadius: 3),
            with: .color(Color(red: 0.75, green: 0.88, blue: 0.72).opacity(0.8))
        )
        drawRoads(&ctx, size, .white)
    }

    private func drawSatellite(_ ctx: inout GraphicsContext, _ size: CGSize) {
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.13),
                    Color(red: 0.15, green: 0.25, blue: 0.28)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            )
        )
        for (rect, opacity) in [
            (CGRect(x: 2,  y: 4,  width: 36, height: 28), 0.65),
            (CGRect(x: 60, y: 10, width: 44, height: 32), 0.55),
            (CGRect(x: 10, y: 50, width: 28, height: 36), 0.60),
            (CGRect(x: 78, y: 54, width: 32, height: 28), 0.50),
        ] as [(CGRect, Double)] {
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: 5),
                with: .color(Color(red: 0.18, green: 0.40, blue: 0.20).opacity(opacity))
            )
        }
        ctx.fill(
            Path(roundedRect: CGRect(x: 34, y: 32, width: 26, height: 20), cornerRadius: 6),
            with: .color(Color(red: 0.15, green: 0.35, blue: 0.58).opacity(0.7))
        )
    }

    private func drawRoads(_ ctx: inout GraphicsContext, _ size: CGSize, _ color: Color) {
        var h = Path()
        h.move(to: CGPoint(x: 0, y: size.height * 0.42))
        h.addLine(to: CGPoint(x: size.width, y: size.height * 0.42))
        ctx.stroke(h, with: .color(color.opacity(0.9)), lineWidth: 3)

        var v = Path()
        v.move(to: CGPoint(x: size.width * 0.50, y: 0))
        v.addLine(to: CGPoint(x: size.width * 0.50, y: size.height))
        ctx.stroke(v, with: .color(color.opacity(0.9)), lineWidth: 2.5)

        var d1 = Path()
        d1.move(to: CGPoint(x: 0, y: size.height * 0.22))
        d1.addLine(to: CGPoint(x: size.width, y: size.height * 0.22))
        ctx.stroke(d1, with: .color(color.opacity(0.55)), lineWidth: 1.5)

        var d2 = Path()
        d2.move(to: CGPoint(x: size.width * 0.28, y: 0))
        d2.addLine(to: CGPoint(x: size.width * 0.28, y: size.height))
        ctx.stroke(d2, with: .color(color.opacity(0.55)), lineWidth: 1.5)
    }
}
