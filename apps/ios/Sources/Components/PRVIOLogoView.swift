import SwiftUI

struct PRVIOLogoView: View {
    var size: CGFloat = 80
    var showBackground: Bool = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, canvas in
            let s  = canvas.width / 1024
            let cx = canvas.width / 2
            let w  = canvas.width
            let h  = canvas.height

            let isDark = scheme == .dark

            // ── BACKGROUND ──────────────────────────────────────────────────
            if showBackground {
                if isDark {
                    ctx.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(Color(red: 0.027, green: 0.043, blue: 0.094)))
                    // center glow
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: w*0.1, y: h*0.05, width: w*0.8, height: h*0.75)),
                        with: .linearGradient(
                            Gradient(colors: [Color(red: 0.15, green: 0.27, blue: 0.80).opacity(0.30), .clear]),
                            startPoint: CGPoint(x: cx, y: 0),
                            endPoint:   CGPoint(x: cx, y: h)
                        )
                    )
                } else {
                    ctx.fill(
                        Path(CGRect(origin: .zero, size: canvas)),
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: Color(red: 0.376, green: 0.682, blue: 1.00),  location: 0.00),
                                .init(color: Color(red: 0.235, green: 0.494, blue: 1.00),  location: 0.35),
                                .init(color: Color(red: 0.118, green: 0.306, blue: 0.847), location: 0.70),
                                .init(color: Color(red: 0.063, green: 0.188, blue: 0.722), location: 1.00),
                            ]),
                            startPoint: .zero,
                            endPoint:   CGPoint(x: w * 0.6, y: h)
                        )
                    )
                    // specular
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: -w*0.05, y: -h*0.05, width: w*0.80, height: h*0.65)),
                        with: .linearGradient(
                            Gradient(colors: [.white.opacity(0.28), .white.opacity(0)]),
                            startPoint: .zero,
                            endPoint:   CGPoint(x: w*0.4, y: h*0.6)
                        )
                    )
                }
            }

            // ── HOUSE GEOMETRY ──────────────────────────────────────────────
            let roofPeakY  = 202 * s
            let eaveY      = 468 * s
            let houseLeft  = 220 * s
            let houseRight = 804 * s
            let wallLeft   = 298 * s
            let wallRight  = 726 * s
            let wallBot    = 808 * s
            let wallR      = 30  * s

            // roof
            var roof = Path()
            roof.move(to:    CGPoint(x: cx,         y: roofPeakY))
            roof.addLine(to: CGPoint(x: houseRight, y: eaveY))
            roof.addLine(to: CGPoint(x: houseLeft,  y: eaveY))
            roof.closeSubpath()

            let roofColor: GraphicsContext.Shading = isDark
                ? .linearGradient(
                    Gradient(colors: [Color(red: 0.333, green: 0.565, blue: 1.00),
                                      Color(red: 0.176, green: 0.376, blue: 0.941)]),
                    startPoint: CGPoint(x: cx, y: roofPeakY),
                    endPoint:   CGPoint(x: cx, y: eaveY))
                : .color(.white.opacity(0.96))

            ctx.fill(roof, with: roofColor)

            // walls
            var wall = Path()
            wall.move(to: CGPoint(x: wallLeft, y: eaveY))
            wall.addLine(to: CGPoint(x: wallRight, y: eaveY))
            wall.addLine(to: CGPoint(x: wallRight, y: wallBot - wallR))
            wall.addArc(center: CGPoint(x: wallRight - wallR, y: wallBot - wallR),
                        radius: wallR, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            wall.addLine(to: CGPoint(x: wallLeft + wallR, y: wallBot))
            wall.addArc(center: CGPoint(x: wallLeft + wallR, y: wallBot - wallR),
                        radius: wallR, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            wall.addLine(to: CGPoint(x: wallLeft, y: eaveY))
            wall.closeSubpath()

            let wallColor: GraphicsContext.Shading = isDark
                ? .linearGradient(
                    Gradient(colors: [Color(red: 0.251, green: 0.439, blue: 1.00),
                                      Color(red: 0.125, green: 0.282, blue: 0.878)]),
                    startPoint: CGPoint(x: wallLeft, y: eaveY),
                    endPoint:   CGPoint(x: wallRight, y: wallBot))
                : .color(.white.opacity(0.97))

            ctx.fill(wall, with: wallColor)

            // ── LOCATION PIN ─────────────────────────────────────────────────
            let wallH = wallBot - eaveY
            let pinCX = cx
            let pinCY = eaveY + wallH * 0.38
            let pinR  = 86 * s
            let tipY  = pinCY + pinR * 2.55

            var pin = Path()
            pin.addArc(center: CGPoint(x: pinCX, y: pinCY),
                       radius: pinR, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            pin.addCurve(to:      CGPoint(x: pinCX,        y: tipY),
                         control1: CGPoint(x: pinCX + pinR, y: pinCY + pinR * 1.55),
                         control2: CGPoint(x: pinCX + pinR * 0.38, y: tipY - pinR * 0.45))
            pin.addCurve(to:      CGPoint(x: pinCX - pinR,  y: pinCY),
                         control1: CGPoint(x: pinCX - pinR * 0.38, y: tipY - pinR * 0.45),
                         control2: CGPoint(x: pinCX - pinR, y: pinCY + pinR * 1.55))
            pin.closeSubpath()

            let pinFill: GraphicsContext.Shading = isDark
                ? .color(.white.opacity(0.96))
                : .color(Color(red: 0.082, green: 0.251, blue: 0.753))

            ctx.fill(pin, with: pinFill)

            // inner circle (hole)
            let hole = Path(ellipseIn: CGRect(
                x: pinCX - pinR * 0.42,
                y: pinCY - pinR * 0.42,
                width:  pinR * 0.84,
                height: pinR * 0.84))

            let holeFill: GraphicsContext.Shading = isDark
                ? .color(Color(red: 0.188, green: 0.376, blue: 0.961))
                : .color(.white.opacity(0.97))

            ctx.fill(hole, with: holeFill)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.224, style: .continuous))
    }
}

#Preview {
    HStack(spacing: 20) {
        PRVIOLogoView(size: 96)
        PRVIOLogoView(size: 96).preferredColorScheme(.dark)
    }
    .padding(24)
    .background(.gray.opacity(0.15))
}
