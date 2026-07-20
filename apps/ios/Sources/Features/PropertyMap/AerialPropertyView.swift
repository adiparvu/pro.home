import SwiftUI

// MARK: - Aerial Property View — animated night-mode 2D illustration
// Mirrors the "heleșteul Pârvu" drone-photo layout:
//   upper-left farm cluster · main house center-left
//   diagonal road right · pond lower-left · trees left edge

struct AerialPropertyView: View {
    var property: PropertyModel? = nil
    var zones: [PropertyZone] = []
    var elements: [PropertyElement] = []
    var cornerRadius: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The Canvas redraws every frame while the timeline runs; pause it the
    /// moment the illustration is off screen or the scene loses foreground,
    /// and keep it a still frame under Reduce Motion.
    @State private var isActive = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60,
                                paused: reduceMotion || !isActive || scenePhase != .active)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                AerialRenderer.draw(ctx: ctx, size: size, t: t, zones: zones)
            }
            .scaleEffect(kenBurns(t), anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .onAppear { isActive = true }
        .onDisappear { isActive = false }
    }

    private func kenBurns(_ t: Double) -> CGFloat {
        1.0 + 0.022 * CGFloat(sin(t * 0.065) * 0.5 + 0.5)
    }
}

// MARK: - Renderer (enum keeps Canvas closure capture-free)

private enum AerialRenderer {

    static func draw(ctx: GraphicsContext, size: CGSize, t: Double, zones: [PropertyZone]) {
        let w = size.width, h = size.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }

        // ── 1. Dark gradient sky / ground ─────────────────────────────
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.04, green: 0.09, blue: 0.06),
                Color(red: 0.03, green: 0.06, blue: 0.04)
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)
        ))

        // ── 2. Agricultural field (right side — dark plowed earth) ─────
        var field = Path()
        field.move(to: p(0.69, 0));  field.addLine(to: p(1, 0))
        field.addLine(to: p(1, 0.82)); field.addLine(to: p(0.80, 1))
        field.addLine(to: p(0.60, 1)); field.addLine(to: p(0.63, 0.60))
        field.addLine(to: p(0.70, 0.52)); field.closeSubpath()
        ctx.fill(field, with: .color(Color(red: 0.11, green: 0.08, blue: 0.05)))
        for i in 0..<10 {
            let yp = CGFloat(i) * 0.10
            var row = Path()
            row.move(to: CGPoint(x: w*(0.70 + yp*0.07), y: h*yp))
            row.addLine(to: CGPoint(x: w, y: h*yp))
            ctx.stroke(row, with: .color(Color(red: 0.16, green: 0.11, blue: 0.07).opacity(0.45)), lineWidth: 0.7)
        }

        // ── 3. Main green terrain ──────────────────────────────────────
        var terrain = Path()
        terrain.move(to: p(0.07, 0.04)); terrain.addLine(to: p(0.73, 0.04))
        terrain.addLine(to: p(0.70, 0.52)); terrain.addLine(to: p(0.63, 0.60))
        terrain.addLine(to: p(0.06, 0.64)); terrain.closeSubpath()
        ctx.fill(terrain, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.07, green: 0.17, blue: 0.09),
                Color(red: 0.05, green: 0.12, blue: 0.07)
            ]),
            startPoint: p(0.4, 0), endPoint: p(0.4, 0.65)
        ))

        // ── 4. Road (diagonal right) ───────────────────────────────────
        var road = Path()
        road.move(to: p(0.68, 0)); road.addLine(to: p(0.74, 0))
        road.addLine(to: p(0.82, 1)); road.addLine(to: p(0.76, 1)); road.closeSubpath()
        ctx.fill(road, with: .color(Color(red: 0.22, green: 0.18, blue: 0.12)))
        var dashes = Path()
        dashes.move(to: p(0.71, 0.02)); dashes.addLine(to: p(0.79, 0.98))
        ctx.stroke(dashes, with: .color(Color(red: 0.38, green: 0.32, blue: 0.22).opacity(0.4)),
                   style: StrokeStyle(lineWidth: 1, dash: [8, 10]))

        // ── 5. Dam / embankment above pond ────────────────────────────
        var dam = Path()
        dam.move(to: p(0.06, 0.64)); dam.addLine(to: p(0.63, 0.60))
        dam.addLine(to: p(0.64, 0.67)); dam.addLine(to: p(0.06, 0.71))
        dam.closeSubpath()
        ctx.fill(dam, with: .color(Color(red: 0.20, green: 0.16, blue: 0.11)))
        for i in 0..<9 {
            let xp = CGFloat(i) * 0.063 + 0.09
            var stone = Path()
            stone.move(to: CGPoint(x: w*xp, y: h*(0.64 - (xp - 0.07)*0.05)))
            stone.addLine(to: CGPoint(x: w*xp, y: h*(0.71 - (xp - 0.07)*0.04)))
            ctx.stroke(stone, with: .color(.black.opacity(0.14)), lineWidth: 0.6)
        }

        // ── 6. Pond / heleșteul ───────────────────────────────────────
        var pond = Path()
        pond.move(to: p(0.06, 0.71)); pond.addLine(to: p(0.64, 0.67))
        pond.addLine(to: p(0.62, 0.94)); pond.addLine(to: p(0.07, 0.96))
        pond.closeSubpath()

        ctx.fill(pond, with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.07, green: 0.20, blue: 0.28),
                Color(red: 0.04, green: 0.13, blue: 0.19)
            ]),
            startPoint: p(0.3, 0.67), endPoint: p(0.3, 0.96)
        ))

        let moonA = CGFloat(0.05 + 0.03 * sin(t * 0.55))
        ctx.fill(pond, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.55, green: 0.80, blue: 1.0).opacity(moonA), location: 0),
                .init(color: .clear, location: 0.68)
            ]),
            center: p(0.24, 0.74), startRadius: 0, endRadius: w * 0.34
        ))

        // shimmer lines
        for i in 0..<4 {
            let yp: CGFloat = 0.745 + CGFloat(i) * 0.055
            let sA = CGFloat(0.10 + 0.08 * sin(t * 1.1 + Double(i) * 1.2))
            var sh = Path()
            sh.move(to: CGPoint(x: w*0.08, y: h*yp))
            sh.addQuadCurve(to: CGPoint(x: w*0.60, y: h*yp),
                            control: CGPoint(x: w*0.34, y: h*(yp - 0.010)))
            ctx.stroke(sh, with: .color(Color.white.opacity(sA)), lineWidth: 0.8)
        }

        // ripple centre 1 (main pond)
        drawRipples(ctx: ctx, center: p(0.27, 0.82), maxR: w*0.14, period: 4.0, alpha: 0.50, t: t, offset: 0)
        // ripple centre 2 (right of pond)
        drawRipples(ctx: ctx, center: p(0.46, 0.77), maxR: w*0.09, period: 3.6, alpha: 0.38, t: t, offset: 0.55)
        // fish ripples
        let fishPts: [(CGFloat, CGFloat, Double)] = [(0.18, 0.85, 0.0), (0.40, 0.89, 0.9), (0.54, 0.75, 1.7)]
        for (fx, fy, fo) in fishPts {
            drawRipples(ctx: ctx, center: p(fx, fy), maxR: w*0.032, period: 2.9, alpha: 0.28, t: t, offset: fo)
        }

        // ── 7. Trees ──────────────────────────────────────────────────
        let trees: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.025, 0.13, 0.043, 0.00), (0.020, 0.26, 0.048, 0.40),
            (0.025, 0.38, 0.040, 0.90), (0.028, 0.50, 0.045, 1.40),
            (0.030, 0.60, 0.040, 0.60), (0.025, 0.85, 0.038, 1.10),
            (0.070, 0.90, 0.034, 0.30), (0.058, 0.07, 0.036, 0.70),
            (0.085, 0.08, 0.029, 1.20),
        ]
        for (tx, ty, tr, tp) in trees {
            drawTree(ctx: ctx, cx: (tx + CGFloat(sin(t*0.75 + tp)*0.009)) * w,
                     cy: ty * h, r: tr * w)
        }

        // ── 8. Buildings ──────────────────────────────────────────────
        // (nx, ny, nw, nh, isMain)
        let bldgs: [(CGFloat, CGFloat, CGFloat, CGFloat, Bool)] = [
            (0.090, 0.050, 0.072, 0.054, false),
            (0.168, 0.068, 0.052, 0.042, false),
            (0.238, 0.046, 0.063, 0.050, false),
            (0.105, 0.117, 0.080, 0.054, false),
            (0.165, 0.128, 0.052, 0.040, false),
            (0.362, 0.295, 0.102, 0.076, true),
            (0.272, 0.218, 0.072, 0.052, false),
            (0.598, 0.388, 0.046, 0.036, false),
        ]
        for (bx, by, bw2, bh2, isMain) in bldgs {
            drawBuilding(ctx: ctx, x: bx*w, y: by*h, bw: bw2*w, bh: bh2*h,
                         isMain: isMain, t: t, phase: Double(bx) * 8)
        }

        // ── 9. Property boundary ──────────────────────────────────────
        var boundary = Path()
        boundary.move(to: p(0.07, 0.04)); boundary.addLine(to: p(0.73, 0.04))
        boundary.addLine(to: p(0.70, 0.52)); boundary.addLine(to: p(0.64, 0.67))
        boundary.addLine(to: p(0.62, 0.94)); boundary.addLine(to: p(0.07, 0.96))
        boundary.addLine(to: p(0.05, 0.71)); boundary.addLine(to: p(0.06, 0.04))
        boundary.closeSubpath()
        ctx.stroke(boundary, with: .color(Color(red: 1.0, green: 0.38, blue: 0.22).opacity(0.50)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [9, 6]))

        // ── 10. Birds ─────────────────────────────────────────────────
        for bi in 0..<3 {
            let period = 22.0
            let off = Double(bi) * period / 3.0
            let bt = (t + off).truncatingRemainder(dividingBy: period)
            let bx2 = CGFloat(bt / period) * (w + 50) - 25
            let by2 = h * CGFloat([0.19, 0.24, 0.16][bi])
            let ba = CGFloat(min(min(bt, period - bt) * 0.4, 1.0))
            var bird = Path()
            bird.move(to: CGPoint(x: bx2-6, y: by2+2))
            bird.addQuadCurve(to: CGPoint(x: bx2+6, y: by2+2),
                              control: CGPoint(x: bx2, y: by2-3))
            ctx.stroke(bird, with: .color(Color(red: 0.14, green: 0.11, blue: 0.08).opacity(ba)),
                       lineWidth: 1.4)
        }

        // ── 11. Vignette ──────────────────────────────────────────────
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0.50),
                .init(color: .black.opacity(0.55), location: 1.0)
            ]),
            center: CGPoint(x: w*0.5, y: h*0.5),
            startRadius: min(w,h)*0.18, endRadius: max(w,h)*0.74
        ))
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static func drawRipples(ctx: GraphicsContext, center: CGPoint,
                                    maxR: CGFloat, period: Double, alpha: CGFloat,
                                    t: Double, offset: Double) {
        for i in 0..<3 {
            let phase = CGFloat((t/period + Double(i)/3.0 + offset).truncatingRemainder(dividingBy: 1.0))
            let r = phase * maxR
            let a = (1.0 - phase) * alpha
            var rp = Path()
            rp.addEllipse(in: CGRect(x: center.x - r, y: center.y - r*0.55, width: r*2, height: r*1.1))
            ctx.stroke(rp, with: .color(Color.cyan.opacity(a)), lineWidth: 1.1)
        }
    }

    private static func drawTree(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat) {
        ctx.fill(Path(ellipseIn: CGRect(x: cx-r*0.9, y: cy+r*0.48, width: r*1.8, height: r*0.52)),
                 with: .color(.black.opacity(0.26)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                 with: .color(Color(red: 0.06, green: 0.17, blue: 0.09)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx-r*0.76, y: cy-r*1.08, width: r*1.52, height: r*1.52)),
                 with: .color(Color(red: 0.10, green: 0.27, blue: 0.14)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx-r*0.45, y: cy-r*1.22, width: r*0.90, height: r*0.90)),
                 with: .color(Color(red: 0.16, green: 0.38, blue: 0.20)))
    }

    private static func drawBuilding(ctx: GraphicsContext, x: CGFloat, y: CGFloat,
                                     bw: CGFloat, bh: CGFloat, isMain: Bool,
                                     t: Double, phase: Double) {
        let center = CGPoint(x: x + bw/2, y: y + bh/2)
        let glowR = isMain ? bw*1.8 : bw*1.5
        let glowA = CGFloat(isMain ? 0.18 + 0.06*sin(t*0.28 + phase)
                                   : 0.10 + 0.04*sin(t*0.35 + phase))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - glowR/2, y: center.y - glowR*0.35,
                                        width: bw + glowR, height: bh + glowR)),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.95, green: 0.70, blue: 0.25).opacity(glowA), location: 0),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: center, startRadius: 0, endRadius: glowR
                 ))

        let wallC = isMain ? Color(red: 0.24, green: 0.21, blue: 0.18)
                           : Color(red: 0.17, green: 0.14, blue: 0.11)
        ctx.fill(Path(CGRect(x: x, y: y, width: bw, height: bh)), with: .color(wallC))

        var roof = Path()
        roof.move(to: CGPoint(x: x-2, y: y))
        roof.addLine(to: CGPoint(x: x+bw+2, y: y))
        roof.addLine(to: CGPoint(x: x+bw/2, y: y - bh*0.30))
        roof.closeSubpath()
        let roofC = isMain ? Color(red: 0.30, green: 0.26, blue: 0.22)
                           : Color(red: 0.22, green: 0.18, blue: 0.14)
        ctx.fill(roof, with: .color(roofC))

        if bw > 18 {
            let winCount = isMain ? 3 : 2
            let winA = CGFloat(0.70 + 0.30*sin(t*0.38 + phase + 1.0))
            let wy = y + bh * 0.27
            for wi in 0..<winCount {
                let wx = x + bw * CGFloat(wi + 1) / CGFloat(winCount + 1)
                ctx.fill(Path(ellipseIn: CGRect(x: wx-3, y: wy-2.5, width: 6, height: 5)),
                         with: .color(Color(red: 0.95, green: 0.80, blue: 0.36).opacity(winA)))
            }
        }
    }
}
