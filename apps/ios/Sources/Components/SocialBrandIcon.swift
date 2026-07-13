import SwiftUI

// MARK: - SocialBrandIcon
//
// The one way a social platform's mark is drawn anywhere in the app.
// Pure SwiftUI vector drawing — no bundled images and no generic SF-symbol
// stand-ins: each supported platform gets its real, instantly recognizable
// mark (Instagram's camera outline, Facebook's "f", WhatsApp's
// bubble-and-phone, LinkedIn's "in", TikTok's chromatic note, X's
// letterform) on its true brand color, clipped to an app-icon rounded
// square. Every stroke width, glyph size and offset derives from `size`,
// so the same component renders crisply as an 18pt chip glyph, a 26–36pt
// form badge, a 46pt profile disc or a 48pt picker tile.
//
// Deliberate exceptions to the design-system font/color tokens, documented
// here once: the letterforms and glyphs below are logo geometry, not text —
// they must stay proportional to the badge and must NOT scale with Dynamic
// Type, so they use fixed `.system(size:)` fonts; and the fills are the
// platforms' official brand colors, which by definition can never come from
// our palette tokens (DesignSystem.swift is intentionally untouched — if a
// shared token home is ever wanted, these constants can migrate there).

struct SocialBrandIcon: View {
    let platform: String
    var size: CGFloat = 36

    // iOS app-icon corner ratio, so badges read as "the real app".
    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
    }

    var body: some View {
        ZStack {
            background
            mark
        }
        .frame(width: size, height: size)
        .clipShape(badgeShape)
        .overlay {
            // Inner hairline keeps the dark badges (TikTok, X) defined on
            // dark glass and adds a subtle bezel to the colored ones.
            badgeShape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        // Decorative by design: every call site labels its control with the
        // platform name (accessibilityLabel or an adjacent Text).
        .accessibilityHidden(true)
    }

    // MARK: Brand fields

    @ViewBuilder
    private var background: some View {
        switch platform {
        case "instagram":
            // Instagram's warm sunset gradient: purple top-right through
            // pink and orange to yellow bottom-left.
            LinearGradient(
                colors: [Brand.igPurple, Brand.igPink, Brand.igOrange, Brand.igYellow],
                startPoint: .topTrailing, endPoint: .bottomLeading)
        case "facebook": Brand.facebook
        case "whatsapp": Brand.whatsapp
        case "linkedin": Brand.linkedin
        case "telegram": Brand.telegram
        case "tiktok", "twitter": Color.black // true brand black in both schemes
        default: Brand.neutral
        }
    }

    // MARK: Marks

    @ViewBuilder
    private var mark: some View {
        switch platform {
        case "instagram": instagramMark
        case "facebook":  facebookMark
        case "whatsapp":  whatsappMark
        case "linkedin":  linkedinMark
        case "tiktok":    tiktokMark
        case "twitter":   xMark
        case "telegram":  telegramMark
        default:
            Image(systemName: "link")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// The camera glyph: rounded-square outline + lens circle + the small
    /// solid dot in the top-right corner. Pure strokes, white on gradient.
    private var instagramMark: some View {
        let stroke = size * 0.062
        let body   = size * 0.60
        let lens   = size * 0.27
        let dot    = size * 0.078
        return ZStack {
            RoundedRectangle(cornerRadius: body * 0.32, style: .continuous)
                .strokeBorder(.white, lineWidth: stroke)
                .frame(width: body, height: body)
            Circle()
                .strokeBorder(.white, lineWidth: stroke)
                .frame(width: lens, height: lens)
            Circle()
                .fill(.white)
                .frame(width: dot, height: dot)
                .offset(x: body * 0.285, y: -body * 0.285)
        }
    }

    /// The lowercase "f" letterform, slightly right of center with its
    /// descender running off the bottom edge — cropped by the badge's
    /// clip shape exactly like the brand lockup.
    private var facebookMark: some View {
        Text(verbatim: "f")
            .font(.system(size: size * 0.86, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .offset(x: size * 0.04, y: size * 0.14)
    }

    /// Speech-bubble outline with the pointed tail at the lower left and a
    /// solid handset inside — WhatsApp's flat glyph, white on green.
    private var whatsappMark: some View {
        let bubble = size * 0.64
        return ZStack {
            SpeechBubbleOutline()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.058,
                                                   lineCap: .round,
                                                   lineJoin: .round))
                .frame(width: bubble, height: bubble)
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .offset(x: size * 0.01, y: -size * 0.015)
    }

    /// The "in" wordmark fragment, bold white on LinkedIn blue.
    private var linkedinMark: some View {
        Text(verbatim: "in")
            .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .kerning(-size * 0.012)
            .offset(y: -size * 0.02)
    }

    /// The musical note drawn three times — cyan copy offset up-left, red
    /// copy offset down-right, white on top. That chromatic echo IS the
    /// TikTok look.
    private var tiktokMark: some View {
        let d = size * 0.035
        return ZStack {
            tiktokNote.foregroundStyle(Brand.tiktokCyan).offset(x: -d, y: -d)
            tiktokNote.foregroundStyle(Brand.tiktokRed).offset(x: d, y: d)
            tiktokNote.foregroundStyle(.white)
        }
    }

    private var tiktokNote: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.50, weight: .bold))
    }

    /// The heavy uppercase X letterform, white on black.
    private var xMark: some View {
        Text(verbatim: "X")
            .font(.system(size: size * 0.56, weight: .heavy))
            .foregroundStyle(.white)
    }

    /// Telegram's paper plane — the one brand whose mark a symbol genuinely
    /// matches — tilted onto the brand's sky blue.
    private var telegramMark: some View {
        Image(systemName: "paperplane.fill")
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(.white)
            .offset(x: -size * 0.02, y: size * 0.02)
    }
}

// MARK: - Speech bubble outline (WhatsApp)
//
// A circle opened at the lower left, closed into a pointed tail: the arc
// runs the long way from the tail's upper attachment (148°) over the top
// and right down to its lower attachment (112°), then out to the apex.
// Angles are in SwiftUI's flipped space (0° right, 90° bottom), where
// `clockwise: false` traverses increasing angles.
private struct SpeechBubbleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let apexAngle = Angle.degrees(132).radians
        let apex = CGPoint(x: center.x + 1.30 * radius * cos(apexAngle),
                           y: center.y + 1.30 * radius * sin(apexAngle))
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(148), endAngle: .degrees(112),
                    clockwise: false)
        path.addLine(to: apex)
        path.closeSubpath()
        return path
    }
}

// MARK: - Official brand colors
//
// Kept private to this file on purpose: nothing else in the app is allowed
// to paint "Facebook blue" — surfaces that need a platform accent for text
// or rings read `SocialLink.platformColor`, which mirrors these values.
private enum Brand {
    static let facebook   = Color(red: 0.094, green: 0.467, blue: 0.949) // #1877F2
    static let whatsapp   = Color(red: 0.145, green: 0.827, blue: 0.400) // #25D366
    static let linkedin   = Color(red: 0.039, green: 0.400, blue: 0.761) // #0A66C2
    static let telegram   = Color(red: 0.133, green: 0.620, blue: 0.851) // #229ED9
    static let igPurple   = Color(red: 0.514, green: 0.227, blue: 0.706) // #833AB4
    static let igPink     = Color(red: 0.882, green: 0.188, blue: 0.424) // #E1306C
    static let igOrange   = Color(red: 0.969, green: 0.518, blue: 0.216) // #F77737
    static let igYellow   = Color(red: 0.988, green: 0.686, blue: 0.271) // #FCAF45
    static let tiktokCyan = Color(red: 0.145, green: 0.957, blue: 0.933) // #25F4EE
    static let tiktokRed  = Color(red: 0.996, green: 0.173, blue: 0.333) // #FE2C55
    static let neutral    = Color(red: 0.420, green: 0.470, blue: 0.550) // "other"
}

#Preview("All platforms, all sizes") {
    let platforms = ["instagram", "facebook", "whatsapp", "linkedin",
                     "tiktok", "twitter", "telegram", "other"]
    return VStack(spacing: 24) {
        ForEach([CGFloat(18), 28, 36, 48], id: \.self) { s in
            HStack(spacing: 12) {
                ForEach(platforms, id: \.self) { p in
                    SocialBrandIcon(platform: p, size: s)
                }
            }
        }
    }
    .padding()
}
