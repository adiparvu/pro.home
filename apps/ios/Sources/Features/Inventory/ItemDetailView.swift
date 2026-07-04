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
    @State private var showLocationPicker = false

    private var live: InventoryItem { service.items.first { $0.id == item.id } ?? item }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerSection
                        detailsCard
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
            LoanItemSheet { borrower, returnDate in Task { await service.loanOut(live, to: borrower, expectedReturn: returnDate) } }
        }
        .confirmationDialog("Mark as Returned?", isPresented: $showReturnConfirm, titleVisibility: .visible) {
            Button("Yes, mark returned") { HapticFeedback.success(); Task { await service.markReturned(live) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let loan = live.currentLoan {
                Text("\"\(live.name)\" loaned to \(loan.borrowerName) will be marked as returned.")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 10) {
            ColoredIconBadge(icon: live.categoryIcon, color: live.categoryColor, size: 72)
            Text(live.name).font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
            HStack(spacing: 8) {
                conditionBadge
                Text(LocalizedStringKey(live.location.capitalized))
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.top, AppSpacing.xxs)
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
                if live.purchasePrice > 0    { dRow("eurosign.circle.fill", "Value", "€\(Int(live.purchasePrice))"); rowDiv }
                if let pd = live.purchaseDate {
                    dRow("calendar", "Purchased", pd.formatted(date: .abbreviated, time: .omitted))
                    rowDiv
                }
                dRow(warrantyIcon, "Warranty", warrantyText, color: warrantyColor)
                if !live.loanHistory.isEmpty {
                    rowDiv
                    Button { withAnimation { showHistory.toggle() } } label: {
                        dRow("clock.arrow.trianglehead.counterclockwise.rotate.90", "Loan History", "\(live.loanHistory.count)")
                    }.buttonStyle(.plain)
                    if showHistory {
                        ForEach(live.loanHistory) { loan in
                            rowDiv
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loan.borrowerName).font(.system(size: 13)).foregroundStyle(.primary)
                                    Text("\(loan.daysOut) days · returned \(loan.returnedAt?.formatted(date: .abbreviated, time: .omitted) ?? "-")")
                                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
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
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
            Text(label).font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(color)
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
                    if live.isLoaned {
                        Text("OUT").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(.orange.opacity(0.15), in: Capsule())
                    } else {
                        Text("IN").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.15), in: Capsule())
                    }
                }
                if let loan = live.currentLoan {
                    VStack(spacing: 6) {
                        loanRow("Borrower", loan.borrowerName)
                        loanRow("Loaned", loan.loanedAt.formatted(date: .abbreviated, time: .omitted))
                        loanRow("Days out", "\(loan.daysOut) day\(loan.daysOut == 1 ? "" : "s")", highlight: loan.daysOut > 7)
                        if let ret = loan.expectedReturnDate {
                            loanRow("Expected return", ret.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .padding(AppSpacing.md).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    Button { HapticFeedback.impact(.medium); showReturnConfirm = true } label: {
                        Label("Mark as Returned", systemImage: "checkmark.circle.fill")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                            .background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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

    private func loanRow(_ label: LocalizedStringKey, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            Spacer()
            Text(value).font(.system(size: 13, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? .orange : Color.primary.opacity(AppOpacity.emphasis))
        }
    }

    private var qrCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("QR Code", systemImage: "qrcode").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    Text("Scan to identify").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                QRCodeImage(content: live.qrContent, size: 160).frame(maxWidth: .infinity)
                Button { shareQR() } label: {
                    Label("Share / Print", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func shareQR() {
        let renderer = ImageRenderer(content: QRCodeImage(content: live.qrContent, size: 300))
        renderer.scale = 3.0
        guard let img = renderer.uiImage else { return }
        let vc = UIActivityViewController(activityItems: [img], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }

    private var locationTrackerCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Location & Tracker", systemImage: "location.fill")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Spacer()
                    if live.hasLocation { Text("📍").font(.system(size: 14)) }
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
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if !live.trackerIdentifier.isEmpty {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                        Text("Tracker: \(live.trackerIdentifier)")
                            .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.65))
                        Spacer()
                    }
                    .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
                Button { showLocationPicker = true } label: {
                    Label(LocalizedStringKey(live.hasLocation ? "Edit Location & Tracker" : "Set Location & Tracker"),
                          systemImage: live.hasLocation ? "pencil" : "plus.circle.fill")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
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
                        Text("ON").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                            .background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.15), in: Capsule())
                    } else {
                        Text("OFF").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary.opacity(0.3))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3).background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                    }
                }
                Text("Anyone who scans the QR code will see a web page with your contact details so they can return the item.")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4)).lineSpacing(2)
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
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func publicRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.65))
            Spacer()
        }
    }

    private var notesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text").font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text(live.notes).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8))
            }
        }
    }
}
