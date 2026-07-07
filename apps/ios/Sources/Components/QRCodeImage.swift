import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QRCodeImage
//
// One premium QR renderer shared by every screen that shows a code (inventory
// items, chat invites, 2FA enrolment). Modules are drawn as the PRVIO brand
// gradient masked through the generated matrix, on a soft white card, with an
// optional centre mark. Correction level H (30% recovery) keeps it scannable
// even with the centre badge covering the middle modules.
//
// The `.plain` style drops the gradient and centre mark for near-black modules —
// used for authenticator QR codes, where third-party scanners want maximum
// contrast and no obstruction.

struct QRCodeImage: View {
    let content: String
    var size: CGFloat = 200
    var style: Style = .brand

    enum Style {
        case brand   // gradient modules + centre brand mark (in-app display, sharing)
        case plain   // high-contrast dark modules, no centre mark (authenticator QR)
    }

    // The generated matrix as a white-on-transparent mask, cached so we don't
    // re-run CoreImage on every layout pass.
    private var mask: UIImage? { Self.maskCache.image(for: content) }

    private var corner: CGFloat { AppRadius.xl }
    private var quietZone: CGFloat { size * 0.09 }

    var body: some View {
        Group {
            if let mask {
                ZStack {
                    modules
                        .mask(
                            Image(uiImage: mask)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                        )
                    if style == .brand { centerMark }
                }
                .frame(width: size, height: size)
                .padding(quietZone)
                .background(.white, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: size + quietZone * 2, height: size + quietZone * 2)
                    .overlay(
                        Image(systemName: "qrcode")
                            .font(.system(size: size * 0.3))
                            .foregroundStyle(Color.primary.opacity(0.15))
                    )
            }
        }
    }

    // MARK: Foreground fill

    @ViewBuilder private var modules: some View {
        switch style {
        case .brand:
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.20, blue: 0.52),
                         Color(red: 0.36, green: 0.20, blue: 0.68)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .plain:
            // Near-black rather than pure black — softer, still well above the
            // contrast ratio scanners need.
            Color(red: 0.09, green: 0.09, blue: 0.13)
        }
    }

    // A rounded white knockout carrying the PRV House "P" brand mark, centred over
    // the matrix — the same letterform the web app stamps into its QR codes, so a
    // code looks identical whichever platform generated it.
    private var centerMark: some View {
        let badge = size * 0.24
        return RoundedRectangle(cornerRadius: badge * 0.28, style: .continuous)
            .fill(.white)
            .frame(width: badge, height: badge)
            .overlay(
                // The approved monogram (P with the roof) replaces the old
                // letterform — same white badge, same footprint.
                Image("BrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.20, blue: 0.52),
                                     Color(red: 0.36, green: 0.20, blue: 0.68)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: badge * 0.66, height: badge * 0.66)
            )
            .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
    }

    // MARK: - Matrix generation (cached)

    private final class MaskCache {
        private var cache: [String: UIImage] = [:]
        private let ctx = CIContext()

        func image(for content: String) -> UIImage? {
            if let hit = cache[content] { return hit }
            guard let img = render(content) else { return nil }
            cache[content] = img
            return img
        }

        private func render(_ content: String) -> UIImage? {
            guard !content.isEmpty else { return nil }
            let filter = CIFilter.qrCodeGenerator()
            filter.setValue(Data(content.utf8), forKey: "inputMessage")
            filter.setValue("H", forKey: "inputCorrectionLevel")
            guard var out = filter.outputImage else { return nil }
            // Matrix comes as black modules on white. Invert (modules→white) then
            // mask-to-alpha so modules become opaque and the ground transparent —
            // exactly the mask SwiftUI needs to paint the gradient through.
            out = out.applyingFilter("CIColorInvert")
            out = out.applyingFilter("CIMaskToAlpha")
            let scaled = out.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
            guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
            return UIImage(cgImage: cg)
        }
    }

    private static let maskCache = MaskCache()
}

// MARK: - PRV House "P" brand mark
//
// The canonical PRV House letterform, drawn from the same path the web uses
// (100×100 viewBox): a solid stem plus a bowl with an even-odd counter cut out.
private struct PRVBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        // Stem: M18 10 h28 v80 h-28 Z
        path.move(to: p(18, 10))
        path.addLine(to: p(46, 10))
        path.addLine(to: p(46, 90))
        path.addLine(to: p(18, 90))
        path.closeSubpath()
        // Bowl outer: M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z
        path.move(to: p(46, 10))
        path.addLine(to: p(68, 10))
        path.addQuadCurve(to: p(90, 33), control: p(90, 10))
        path.addQuadCurve(to: p(68, 56), control: p(90, 56))
        path.addLine(to: p(46, 56))
        path.closeSubpath()
        // Counter cutout (even-odd): M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z
        path.move(to: p(46, 26))
        path.addLine(to: p(65, 26))
        path.addQuadCurve(to: p(74, 33), control: p(74, 26))
        path.addQuadCurve(to: p(65, 40), control: p(74, 40))
        path.addLine(to: p(46, 40))
        path.closeSubpath()
        return path
    }
}
