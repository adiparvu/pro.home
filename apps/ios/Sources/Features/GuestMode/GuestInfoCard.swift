import SwiftUI

// MARK: - GuestRule
//
// The predefined house rules a host can toggle on the Guest Mode screen.
// Raw values are the stable identifiers persisted in AppStorage
// ("prvio.guest.rules_selected", comma-separated), so renaming a case never
// breaks stored selections.

enum GuestRule: String, CaseIterable, Identifiable {
    case noSmoking  = "no_smoking"
    case noPets     = "no_pets"
    case quietHours = "quiet_hours"
    case recycle    = "recycle"
    case noParties  = "no_parties"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .noSmoking:  "nosign"
        case .noPets:     "pawprint"
        case .quietHours: "moon"
        case .recycle:    "arrow.3.trianglepath"
        case .noParties:  "party.popper"
        }
    }

    var title: String {
        switch self {
        case .noSmoking:  String(localized: "guest_rule_no_smoking")
        case .noPets:     String(localized: "guest_rule_no_pets")
        case .quietHours: String(localized: "guest_rule_quiet_hours")
        case .recycle:    String(localized: "guest_rule_recycle")
        case .noParties:  String(localized: "guest_rule_no_parties")
        }
    }

    /// Decodes a persisted comma-separated id list; unknown ids are dropped.
    static func decode(_ stored: String) -> [GuestRule] {
        stored.split(separator: ",").compactMap { GuestRule(rawValue: String($0)) }
    }

    /// Encodes a selection in the catalog's canonical order, so the stored
    /// string (and the shared card) is stable regardless of tap order.
    static func encode(_ rules: [GuestRule]) -> String {
        allCases.filter(rules.contains).map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - WiFiQR
//
// Builds the standard Wi-Fi join payload (`WIFI:T:WPA;S:<ssid>;P:<pass>;;`)
// that iOS and Android cameras recognise natively. Special characters
// (\ ; , : ") are backslash-escaped per the de-facto spec.

enum WiFiQR {
    static func payload(ssid: String, password: String) -> String? {
        let name = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !password.isEmpty else { return nil }
        return "WIFI:T:WPA;S:\(escaped(name));P:\(escaped(password));;"
    }

    private static func escaped(_ raw: String) -> String {
        raw.reduce(into: "") { out, char in
            if char == "\\" || char == ";" || char == "," || char == ":" || char == "\"" {
                out.append("\\")
            }
            out.append(char)
        }
    }
}

// MARK: - GuestTime
//
// Check-in/check-out times persist as a locale-independent "HH:mm" string in
// AppStorage (empty string = not set) and render through the user's locale
// (24h/AM-PM) for display.

enum GuestTime {
    static func date(from stored: String) -> Date? {
        let parts = stored.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    static func stored(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    static func display(_ stored: String) -> String {
        guard let date = date(from: stored) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - GuestInfoCard
//
// The shareable guest sheet: a print-friendly white card with the property
// name and address, the Wi-Fi join QR, the toggled house-rule chips, check-in/
// check-out, the host's phone and free-form notes. The exact same view is
// embedded live in GuestModeView as the "Preview" section and rendered with
// ImageRenderer for the share sheet, so what the host previews is what the
// guest receives. Colors are explicit (not semantic) so the card is identical
// in dark mode, in the preview, and on paper — same approach as
// PropertyPassport's printable pages.

struct GuestInfoCard: View {
    let propertyName: String
    let address: String
    let wifiName: String
    /// `WIFI:` payload; nil hides the QR (never show an empty code).
    let wifiQRPayload: String?
    let rules: [GuestRule]
    let rulesText: String
    /// Display-formatted times / phone; empty hides the field.
    let checkIn: String
    let checkOut: String
    let hostPhone: String
    let notes: String

    private var hasWifi: Bool { !wifiName.isEmpty }
    private var hasRules: Bool { !rules.isEmpty || !rulesText.isEmpty }
    private var hasEssentials: Bool { !checkIn.isEmpty || !checkOut.isEmpty || !hostPhone.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            header
            if hasWifi {
                hairline
                wifiBlock
            }
            if hasRules {
                hairline
                rulesBlock
            }
            if hasEssentials {
                hairline
                essentialsBlock
            }
            if !notes.isEmpty {
                hairline
                notesBlock
            }
            hairline
            footer
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.7)
        )
        .environment(\.colorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: AppSpacing.base) {
            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .background(CardInk.accentGradient,
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(format: String(localized: "Welcome to %@!"), propertyName))
                    .font(AppFont.scaled(19, weight: .bold))
                    .foregroundStyle(CardInk.title)
                if !address.isEmpty {
                    Text(verbatim: address)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(CardInk.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Wi-Fi

    private var wifiBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            blockHeader(icon: "wifi", "WiFi")
            VStack(spacing: AppSpacing.sm) {
                if let wifiQRPayload {
                    QRCodeImage(content: wifiQRPayload, size: 150)
                        .padding(.bottom, AppSpacing.xxs)
                }
                Text(verbatim: wifiName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(CardInk.title)
                if wifiQRPayload != nil {
                    Text("guest_wifi_qr_hint")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(CardInk.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Rules

    private var rulesBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            blockHeader(icon: "list.bullet.clipboard.fill", "House Rules")
            if !rules.isEmpty {
                ChipFlow(spacing: AppSpacing.xs) {
                    ForEach(rules) { rule in
                        HStack(spacing: 5) {
                            Image(systemName: rule.icon)
                                .font(AppFont.scaled(11, weight: .semibold))
                            Text(verbatim: rule.title)
                                .font(AppFont.scaled(12, weight: .semibold))
                        }
                        .foregroundStyle(CardInk.accentStart)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 5)
                        .background(CardInk.accentStart.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(CardInk.accentStart.opacity(0.18), lineWidth: 0.7))
                    }
                }
            }
            if !rulesText.isEmpty {
                Text(verbatim: rulesText)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(CardInk.body)
            }
        }
    }

    // MARK: Essentials

    private var essentialsBlock: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            if !checkIn.isEmpty {
                essentialColumn(icon: "arrow.right.to.line", "guest_checkin", value: checkIn)
            }
            if !checkOut.isEmpty {
                essentialColumn(icon: "arrow.left.to.line", "guest_checkout", value: checkOut)
            }
            if !hostPhone.isEmpty {
                essentialColumn(icon: "phone.fill", "guest_host_phone", value: hostPhone)
            }
        }
    }

    private func essentialColumn(icon: String, _ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppFont.scaled(10, weight: .semibold))
                Text(label)
                    .font(AppFont.scaled(10, weight: .semibold))
                    .tracking(0.4)
            }
            .foregroundStyle(CardInk.secondary)
            Text(verbatim: value)
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(CardInk.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Notes

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            blockHeader(icon: "note.text", "Important Notes")
            Text(verbatim: notes)
                .font(AppFont.scaled(13))
                .foregroundStyle(CardInk.body)
        }
    }

    // MARK: Chrome

    private func blockHeader(icon: String, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
            Text(title)
                .font(AppFont.label)
                .tracking(0.5)
        }
        .foregroundStyle(CardInk.secondary)
    }

    private var hairline: some View {
        Rectangle()
            .fill(CardInk.hairline)
            .frame(height: 0.7)
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "PRVIO")
                .font(AppFont.scaled(11, weight: .heavy))
                .foregroundStyle(CardInk.accentStart)
            Spacer()
            Text(verbatim: AppDate.dayString(from: Date()))
                .font(AppFont.scaled(10))
                .foregroundStyle(CardInk.secondary)
        }
    }
}

// MARK: - Card ink
//
// Explicit print colors for the white card — same philosophy as
// PropertyPassport's pages. The accent pair mirrors QRCodeImage's brand
// gradient so the card and the QR modules on it read as one piece.

private enum CardInk {
    static let title = Color(red: 0.09, green: 0.10, blue: 0.16)
    static let body = Color.black.opacity(0.72)
    static let secondary = Color.black.opacity(0.48)
    static let hairline = Color.black.opacity(0.08)
    static let accentStart = Color(red: 0.16, green: 0.20, blue: 0.52)
    static let accentEnd = Color(red: 0.36, green: 0.20, blue: 0.68)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - ChipFlow
//
// A minimal wrapping layout for the card's rule chips (variable-width
// capsules that flow onto new lines). Local to the card so the shared image
// never truncates a chip row.

private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxWidth == .infinity ? widest : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
