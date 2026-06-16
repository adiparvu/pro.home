import SwiftUI
import MapKit
import CoreLocation

// MARK: - Item Detail

struct ItemDetailView: View {
    let item: InventoryItem
    @ObservedObject var service: InventoryService
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
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Item Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(.primary) }
            }
        }
        .sheet(isPresented: $showLocationPicker) {
            ItemLocationSheet(item: live) { updated in service.update(updated) }
        }
        .sheet(isPresented: $showPublicContact) {
            PublicContactSheet(item: live) { updated in
                service.update(updated)
                Task { await service.syncPublicProfile(for: updated) }
            }
        }
        .sheet(isPresented: $showLoan) {
            LoanItemSheet { borrower, returnDate in service.loanOut(live, to: borrower, expectedReturn: returnDate) }
        }
        .confirmationDialog("Mark as Returned?", isPresented: $showReturnConfirm, titleVisibility: .visible) {
            Button("Yes, mark returned") { HapticFeedback.success(); service.markReturned(live) }
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
                Text(live.location.capitalized)
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.top, 4)
    }

    private var conditionBadge: some View {
        let map: [String: Color] = ["excellent": Color(red: 0.2, green: 0.8, blue: 0.3), "good": Color.accentColor, "fair": .orange, "poor": Color.red]
        let color = map[live.condition] ?? .gray
        return Text(live.condition.capitalized)
            .font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
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
                                Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.35)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(loan.borrowerName).font(.system(size: 13)).foregroundStyle(.primary)
                                    Text("\(loan.daysOut) days · returned \(loan.returnedAt?.formatted(date: .abbreviated, time: .omitted) ?? "-")")
                                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dRow(_ icon: String, _ label: String, _ value: String, color: Color = Color.primary.opacity(0.55)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
            Text(label).font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(color)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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
        guard let exp = live.warrantyExpiresAt else { return "None" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        if days < 0 { return "Expired" }
        return "Until \(exp.formatted(date: .abbreviated, time: .omitted))"
    }
    private var warrantyColor: Color {
        switch live.warrantyStatus {
        case .valid:        return Color(red: 0.3, green: 0.85, blue: 0.5)
        case .expiringSoon: return .orange
        case .expired:      return .red
        case .none:         return Color.primary.opacity(0.35)
        }
    }

    private var loanCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Label("Loan Status", systemImage: "arrow.uturn.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    if live.isLoaned {
                        Text("OUT").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(.orange.opacity(0.15), in: Capsule())
                    } else {
                        Text("IN").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.15), in: Capsule())
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
                    .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    Button { HapticFeedback.impact(.medium); showReturnConfirm = true } label: {
                        Label("Mark as Returned", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                } else {
                    Button { HapticFeedback.impact(.medium); showLoan = true } label: {
                        Label("Loan Out to Someone", systemImage: "arrow.uturn.right.circle.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func loanRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
            Spacer()
            Text(value).font(.system(size: 13, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? .orange : Color.primary.opacity(0.7))
        }
    }

    private var qrCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack {
                    Label("QR Code", systemImage: "qrcode").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    Text("Scan to identify").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.35))
                }
                QRCodeImage(content: live.qrContent, size: 160).frame(maxWidth: .infinity)
                Button { shareQR() } label: {
                    Label("Share / Print", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.7))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
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
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    if live.hasLocation { Text("📍").font(.system(size: 14)) }
                    if !live.trackerType.isEmpty {
                        Text(live.trackerType == "airtag" ? "🏷 AirTag" : live.trackerType.capitalized)
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                if live.hasLocation, let lat = live.latitude, let lon = live.longitude {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )), annotationItems: [InventoryMapPin(lat: lat, lon: lon)]) { pin in
                        MapMarker(coordinate: pin.coordinate, tint: live.categoryColor)
                    }
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                    Label(live.hasLocation ? "Edit Location & Tracker" : "Set Location & Tracker",
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
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                    Spacer()
                    if live.publicProfile != nil {
                        Text("ON").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.3))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.15), in: Capsule())
                    } else {
                        Text("OFF").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.primary.opacity(0.3))
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.primary.opacity(0.07), in: Capsule())
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
                    Label(live.publicProfile == nil ? "Set Up Contact Info" : "Edit Contact Info",
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
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.35)).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.65))
            Spacer()
        }
    }

    private var notesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                Text(live.notes).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8))
            }
        }
    }
}

// MARK: - Public Contact Sheet

private struct PublicContactSheet: View {
    let item: InventoryItem
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ownerName: String
    @State private var ownerPhone: String
    @State private var ownerAddress: String
    @State private var propertyName: String
    @State private var isEnabled: Bool

    init(item: InventoryItem, onSave: @escaping (InventoryItem) -> Void) {
        self.item = item; self.onSave = onSave
        _ownerName    = State(initialValue: item.publicProfile?.ownerName ?? "")
        _ownerPhone   = State(initialValue: item.publicProfile?.ownerPhone ?? "")
        _ownerAddress = State(initialValue: item.publicProfile?.ownerAddress ?? "")
        _propertyName = State(initialValue: item.publicProfile?.propertyName ?? "")
        _isEnabled    = State(initialValue: item.publicProfile?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                Text("Show on public QR page").font(.system(size: 15)).foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: $isEnabled).tint(.accentColor).labelsHidden()
                            }.padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        if isEnabled {
                            VStack(spacing: 0) {
                                pField("person.fill", "Your name", $ownerName)
                                div
                                pField("phone.fill", "Phone number", $ownerPhone, keyboard: .phonePad)
                                div
                                pField("house.fill", "Home address", $ownerAddress)
                                div
                                pField("building.fill", "Property name", $propertyName)
                            }
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            Text("This information will be visible to anyone who scans the QR code of this item. Only share what you are comfortable with.")
                                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.35))
                                .multilineTextAlignment(.center).padding(.horizontal, 8)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Lost & Found Card").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        if isEnabled {
                            updated.publicProfile = PublicProfile(ownerName: ownerName, ownerPhone: ownerPhone,
                                                                  ownerAddress: ownerAddress, propertyName: propertyName, isEnabled: true)
                        } else {
                            updated.publicProfile = nil
                        }
                        onSave(updated); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func pField(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}

// MARK: - Loan Sheet

private struct LoanItemSheet: View {
    let onSave: (String, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var borrower = ""
    @State private var hasReturnDate = false
    @State private var returnDate = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                            TextField("Borrower's name", text: $borrower).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                        }.padding(.horizontal, 16).padding(.vertical, 14)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                            Text("Expected return").font(.system(size: 15)).foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: $hasReturnDate).tint(.accentColor).labelsHidden()
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if hasReturnDate {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
                            HStack(spacing: 12) {
                                Color.clear.frame(width: 28)
                                DatePicker("Return by", selection: $returnDate, in: Date()..., displayedComponents: .date)
                                    .tint(.accentColor)
                            }.padding(.horizontal, 16).padding(.vertical, 8)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                    Text("You'll get reminders after 1, 3, 7, 14, 30 and 90 days if the item isn't returned.")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, 8)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }
            .navigationTitle("Loan Out Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onSave(borrower.trimmingCharacters(in: .whitespaces), hasReturnDate ? returnDate : nil)
                        HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .disabled(borrower.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Location + Tracker Sheet

private struct ItemLocationSheet: View {
    let item: InventoryItem
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()

    @State private var latText: String
    @State private var lonText: String
    @State private var trackerType: String
    @State private var trackerIdentifier: String

    private let trackerTypes = ["", "airtag", "tile", "gps", "other"]

    init(item: InventoryItem, onSave: @escaping (InventoryItem) -> Void) {
        self.item = item; self.onSave = onSave
        _latText           = State(initialValue: item.latitude.map { String(format: "%.6f", $0) } ?? "")
        _lonText           = State(initialValue: item.longitude.map { String(format: "%.6f", $0) } ?? "")
        _trackerType       = State(initialValue: item.trackerType)
        _trackerIdentifier = State(initialValue: item.trackerIdentifier)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let lat = Double(latText), let lon = Double(lonText) {
                            Map(coordinateRegion: .constant(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            )), annotationItems: [InventoryMapPin(lat: lat, lon: lon)]) { pin in
                                MapMarker(coordinate: pin.coordinate, tint: .blue)
                            }
                            .frame(maxWidth: .infinity).frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        Button { locMgr.requestLocation() } label: {
                            Label("Use Current Location", systemImage: "location.fill")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                        VStack(spacing: 0) {
                            coordRow("Latitude", $latText)
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                            coordRow("Longitude", $lonText)
                        }
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TRACKER TYPE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(trackerTypes, id: \.self) { t in
                                        Button { trackerType = t } label: {
                                            Text(t.isEmpty ? "None" : (t == "airtag" ? "AirTag" : t.capitalized))
                                                .font(.system(size: 13, weight: trackerType == t ? .semibold : .regular))
                                                .foregroundStyle(trackerType == t ? Color.black : Color.primary.opacity(0.7))
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                                .background(trackerType == t ? Color.white : Color.primary.opacity(0.08), in: Capsule())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !trackerType.isEmpty {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                    TextField("Tracker name / serial (optional)", text: $trackerIdentifier)
                                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                                }.padding(.horizontal, 16).padding(.vertical, 13)
                            }
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            if trackerType == "airtag" {
                                GlassCard(padding: 14) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                                        Text("Apple AirTag live location requires the Find My app (private Apple API). Save the name here as a reference, then open Find My for live tracking.")
                                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Location & Tracker").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.latitude = Double(latText)
                        updated.longitude = Double(lonText)
                        updated.trackerType = trackerType
                        updated.trackerIdentifier = trackerIdentifier
                        onSave(updated)
                        HapticFeedback.success()
                        dismiss()
                    }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .onChange(of: locMgr.location) { _, loc in
                guard let loc else { return }
                latText = String(format: "%.6f", loc.coordinate.latitude)
                lonText = String(format: "%.6f", loc.coordinate.longitude)
            }
        }
    }

    private func coordRow(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            TextField("0.000000", text: binding).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.7)).tint(.accentColor)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
}
