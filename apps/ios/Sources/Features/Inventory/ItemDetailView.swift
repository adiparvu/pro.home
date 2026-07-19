import SwiftUI
import MapKit
import CoreLocation

// MARK: - Item Detail

struct ItemDetailView: View {
    let item: InventoryItem
    var service: InventoryService
    @Environment(\.dismiss) private var dismiss
    @State private var showLoan = false
    @State private var showReturnConfirm = false
    @State private var showHistory = false
    @State private var showPublicContact = false
    /// In-app preview of the item's live public QR page (IMG_8685) — the
    /// same real-page preview the Lost & Found card gained in b1165.
    @State private var showQRPagePreview = false
    @State private var showLocationPicker = false

    private var live: InventoryItem { service.items.first { $0.id == item.id } ?? item }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection
                        detailsCard
                        InventoryPhotosCard(itemId: live.id)
                        loanCard
                        qrCard
                        locationTrackerCard
                        publicContactCard
                        if !live.notes.isEmpty { notesCard }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Item Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(.primary) }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            ItemLocationSheet(item: live) { updated in Task { await service.update(updated) } }
        }
        .sheet(isPresented: $showPublicContact) {
            PublicContactSheet(item: live) { updated in
                Task {
                    await service.update(updated)
                    await service.syncPublicProfile(for: updated)
                }
            }
        }
        .sheet(isPresented: $showLoan) {
            LoanItemSheet(suggestions: service.items.recentBorrowers) { borrower, returnDate in
                Task { await service.loanOut(live, to: borrower, expectedReturn: returnDate) }
            }
        }
        .confirmationDialog("Mark as Returned?", isPresented: $showReturnConfirm, titleVisibility: .visible) {
            Button("Yes, mark returned") { HapticFeedback.success(); Task { await service.markReturned(live) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let loan = live.currentLoan {
                Text("\"\(live.name)\" loaned to \(loan.borrowerName) will be marked as returned.")
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Sections

    private var headerSection: some View {
        let tint = live.categoryColor
        return VStack(spacing: 14) {
            // Photo avatar when one is set — the category icon stays as a
            // corner badge — otherwise the icon in a soft glass disc.
            ZStack(alignment: .bottomTrailing) {
                if let photo = InventoryImageStore.load(for: live.id) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: tint.opacity(0.45), radius: 18, y: 8)
                    ZStack {
                        Circle()
                            .fill(tint)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        Image(systemName: live.categoryIcon)
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(.white)
                    }
                    .offset(x: 4, y: 4)
                } else {
                    Image(systemName: live.categoryIcon)
                        .font(AppFont.scaled(38, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 96, height: 96)
                        .glassCircle()
                }
            }

            Text(live.name)
                .font(AppFont.scaled(24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                conditionBadge
                if live.purchasePrice > 0 {
                    heroChip(CurrencyService.money(live.purchasePrice, code: "EUR", whole: true), icon: "eurosign.circle.fill")
                }
                if !live.location.isEmpty {
                    heroChip(InventoryLabels.location(live.location), icon: "mappin.circle.fill")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RadialGradient(colors: [.white.opacity(0.16), .clear],
                                   center: .top, startRadius: 6, endRadius: 220)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
        .shadow(color: tint.opacity(0.25), radius: 20, y: 10)
    }

    private func heroChip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(AppFont.scaled(10, weight: .semibold))
            Text(verbatim: text).font(AppFont.caption)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private var conditionBadge: some View {
        let map: [String: Color] = ["excellent": Color(red: 0.2, green: 0.8, blue: 0.3), "good": Color.accentColor, "fair": .orange, "poor": Color.red]
        let color = map[live.condition] ?? .gray
        return Text(LocalizedStringKey(live.condition.capitalized))
            .font(AppFont.caption).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var detailsCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                if !live.brand.isEmpty       { dRow("building.2.fill", "Brand",   live.brand);       rowDiv }
                if !live.serialNumber.isEmpty { dRow("number", "Serial",           live.serialNumber); rowDiv }
                if live.purchasePrice > 0    { dRow("eurosign.circle.fill", "Value", CurrencyService.money(live.purchasePrice, code: "EUR", whole: true)); rowDiv }
                if let pd = live.purchaseDate {
                    dRow("calendar", "Purchased", pd.formatted(date: .abbreviated, time: .omitted))
                    rowDiv
                }
                dRow(warrantyIcon, "Warranty", warrantyText, color: warrantyColor)
                if let receipt = InventoryImageStore.loadReceipt(for: live.id) {
                    rowDiv
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.image").font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
                        Text("inv_receipt").font(AppFont.scaled(14)).foregroundStyle(.primary)
                        Spacer()
                        Image(uiImage: receipt)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                }
                if !live.loanHistory.isEmpty {
                    rowDiv
                    Button { withAnimation(AppMotion.state) { showHistory.toggle() } } label: {
                        dRow("clock.arrow.trianglehead.counterclockwise.rotate.90", "Loan History", "\(live.loanHistory.count)")
                    }.buttonStyle(.plain)
                    if showHistory {
                        ForEach(live.loanHistory) { loan in
                            rowDiv
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill").font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loan.borrowerName).font(AppFont.scaled(13)).foregroundStyle(.primary)
                                    Text(String(format: String(localized: "loan_hist_line"),
                                                Self.dayCount(loan.daysOut),
                                                loan.returnedAt?.formatted(date: .abbreviated, time: .omitted) ?? "-"))
                                        .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dRow(_ icon: String, _ label: LocalizedStringKey, _ value: String, color: Color = Color.primary.opacity(0.55)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
            Text(label).font(AppFont.scaled(14)).foregroundStyle(.primary)
            Spacer()
            Text(value).font(AppFont.scaled(13)).foregroundStyle(color)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
    }

    private var rowDiv: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private var warrantyIcon: String {
        switch live.warrantyStatus {
        case .valid:         return "checkmark.shield.fill"
        case .expiringSoon:  return "exclamationmark.shield.fill"
        case .expired:       return "xmark.shield.fill"
        case .none:          return "shield.slash.fill"
        }
    }
    private var warrantyText: String {
        guard let exp = live.warrantyExpiresAt else { return String(localized: "None") }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        if days < 0 { return String(localized: "Expired") }
        return String(localized: "Until \(exp.formatted(date: .abbreviated, time: .omitted))")
    }
    private var warrantyColor: Color {
        switch live.warrantyStatus {
        case .valid:        return Color.brandSuccess
        case .expiringSoon: return .orange
        case .expired:      return .red
        case .none:         return Color.primary.opacity(AppOpacity.disabled)
        }
    }

    private var loanCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Loan Status", systemImage: "arrow.uturn.right.circle.fill")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    // Plain-Romanian states — "Împrumutat" / "Disponibil" —
                    // instead of the cryptic IN/OUT badges.
                    if live.isLoaned {
                        Text("inv_status_loaned").font(AppFont.scaled(11, weight: .bold)).foregroundStyle(.orange)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(.orange.opacity(0.15), in: Capsule())
                    } else {
                        Text("inv_status_available").font(AppFont.scaled(11, weight: .bold)).foregroundStyle(Color.brandSuccess)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(Color.brandSuccess.opacity(0.15), in: Capsule())
                    }
                }
                if let loan = live.currentLoan {
                    let overdue = loan.expectedReturnDate.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false
                    VStack(spacing: 6) {
                        loanRow("Borrower", loan.borrowerName)
                        loanRow("Loaned", loan.loanedAt.formatted(date: .abbreviated, time: .omitted))
                        loanRow("Days out", Self.dayCount(loan.daysOut), highlight: loan.daysOut > 7)
                        if let ret = loan.expectedReturnDate {
                            loanRow("Expected return",
                                    overdue
                                        ? "\(ret.formatted(date: .abbreviated, time: .omitted)) · \(String(localized: "inv_loan_overdue"))"
                                        : ret.formatted(date: .abbreviated, time: .omitted),
                                    highlight: overdue, tint: Color.brandDanger)
                        }
                    }
                    .padding(AppSpacing.md).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    Button { HapticFeedback.impact(.medium); showReturnConfirm = true } label: {
                        Label("Mark as Returned", systemImage: "checkmark.circle.fill")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.brandSuccess)
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .background(Color.brandSuccess.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                } else {
                    Button { HapticFeedback.impact(.medium); showLoan = true } label: {
                        Label("Loan Out to Someone", systemImage: "arrow.uturn.right.circle.fill")
                            .font(AppFont.footnoteEmphasis).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func loanRow(_ label: LocalizedStringKey, _ value: String,
                         highlight: Bool = false, tint: Color = .orange) -> some View {
        HStack {
            Text(label).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            Spacer()
            Text(value).font(AppFont.scaled(13, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? tint : Color.primary.opacity(AppOpacity.emphasis))
        }
    }

    private var qrCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("QR Code", systemImage: "qrcode").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    Text("Scan to identify").font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                QRCodeImage(content: live.qrContent, size: 160).frame(maxWidth: .infinity)
                // Two icon-only Liquid Glass actions — Share on the left,
                // Print on the right. Prominence comes from the native glass
                // material, not a tinted fill; the glyph carries the meaning.
                HStack(spacing: AppSpacing.md) {
                    qrActionButton("square.and.arrow.up",
                                   label: Locale.appIsRomanian ? "Partajează" : "Share") {
                        if let img = renderQR() { SystemActions.share([img]) }
                    }
                    qrActionButton("printer",
                                   label: Locale.appIsRomanian ? "Printează" : "Print") {
                        if let img = renderQR() {
                            SystemActions.print(image: img,
                                                jobName: live.name.isEmpty ? "PRVIO" : live.name)
                        }
                    }
                }
                // The scanned page itself, one tap away (IMG_8685): the LIVE
                // public page, not a mock — loan status, map, language, all.
                Button {
                    HapticFeedback.impact(.light)
                    showQRPagePreview = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "safari.fill").font(AppFont.scaled(13))
                        Text("lost_preview_page").font(AppFont.scaled(13, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .glassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showQRPagePreview) {
            if let url = URL(string: live.qrContent) {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    private func qrActionButton(_ icon: String, label: String,
                                _ action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity).frame(height: 44)
                .glassCapsule()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// Locale-aware day count ("3 zile", "1 zi", "0 zile") — the b1132
    /// one-unit style; the hand-built "day\(s)" literal leaked English on
    /// Romanian devices (IMG_8685: "0 days").
    private static let dayCountFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day]
        f.unitsStyle = .full
        return f
    }()

    private static func dayCount(_ days: Int) -> String {
        dayCountFormatter.string(from: DateComponents(day: days)) ?? "\(days)"
    }

    private func renderQR() -> UIImage? {
        let renderer = ImageRenderer(content: QRCodeImage(content: live.qrContent, size: 300))
        renderer.scale = 3.0
        return renderer.uiImage
    }

    private var locationTrackerCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Location & Tracker", systemImage: "location.fill")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    if live.hasLocation { Text("📍").font(AppFont.scaled(14)) }
                    if !live.trackerType.isEmpty {
                        Text(LocalizedStringKey(live.trackerType == "airtag" ? "AirTag" : live.trackerType.capitalized))
                            .font(AppFont.label).foregroundStyle(.orange)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                if live.hasLocation, let lat = live.latitude, let lon = live.longitude {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    ))) {
                        Marker(live.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            .tint(live.categoryColor)
                    }
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

                    Button {
                        let q = "\(lat),\(lon)"
                        if let url = URL(string: "maps://?q=\(live.name)&ll=\(q)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open in Maps", systemImage: "map.fill")
                            .font(AppFont.scaled(13, weight: .medium)).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if !live.trackerIdentifier.isEmpty {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                        Text("Tracker: \(live.trackerIdentifier)")
                            .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.65))
                        Spacer()
                    }
                    .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                Button { showLocationPicker = true } label: {
                    Label(LocalizedStringKey(live.hasLocation ? "Edit Location & Tracker" : "Set Location & Tracker"),
                          systemImage: live.hasLocation ? "pencil" : "plus.circle.fill")
                        .font(AppFont.scaled(13, weight: .medium)).foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private var publicContactCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Lost & Found Card", systemImage: "mappin.and.ellipse")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    if live.publicProfile != nil {
                        Text("ON").font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                            .background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.15), in: Capsule())
                    } else {
                        Text("OFF").font(AppFont.scaled(11, weight: .bold)).foregroundStyle(Color.primary.opacity(0.3))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                    }
                }
                Text("Anyone who scans the QR code will see a web page with your contact details so they can return the item.")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4)).lineSpacing(2)
                if let p = live.publicProfile {
                    VStack(spacing: 4) {
                        if !p.ownerName.isEmpty    { publicRow("person.fill",  p.ownerName) }
                        if !p.ownerPhone.isEmpty   { publicRow("phone.fill",   p.ownerPhone) }
                        if !p.ownerAddress.isEmpty { publicRow("house.fill",   p.ownerAddress) }
                    }
                    .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                Button { HapticFeedback.impact(.medium); showPublicContact = true } label: {
                    Label(LocalizedStringKey(live.publicProfile == nil ? "Set Up Contact Info" : "Edit Contact Info"),
                          systemImage: live.publicProfile == nil ? "plus.circle.fill" : "pencil")
                        .font(AppFont.scaled(13, weight: .medium)).foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func publicRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).frame(width: 16)
            Text(text).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.65))
            Spacer()
        }
    }

    private var notesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text(live.notes).font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(0.8))
            }
        }
    }
}
