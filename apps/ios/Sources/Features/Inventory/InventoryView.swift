import SwiftUI
import VisionKit
import CoreImage.CIFilterBuiltins
import UserNotifications
import MapKit
import CoreLocation

// MARK: - Models

private let itemFoundBaseURL = "https://kwcanenheihuylaymwsl.supabase.co/functions/v1/item-found"

struct PublicProfile: Codable {
    var ownerName: String = ""
    var ownerPhone: String = ""
    var ownerAddress: String = ""
    var propertyName: String = ""
    var isEnabled: Bool = true
}

struct LoanRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var borrowerName: String
    var loanedAt: Date = Date()
    var expectedReturnDate: Date?
    var returnedAt: Date?
    var isReturned: Bool { returnedAt != nil }
    var daysOut: Int { Calendar.current.dateComponents([.day], from: loanedAt, to: returnedAt ?? Date()).day ?? 0 }
}

struct InventoryItem: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var category: String = "tools"
    var location: String = "garage"
    var brand: String = ""
    var serialNumber: String = ""
    var purchaseDate: Date?
    var purchasePrice: Double = 0
    var warrantyExpiresAt: Date?
    var condition: String = "good"
    var notes: String = ""
    var currentLoan: LoanRecord?
    var loanHistory: [LoanRecord] = []
    var publicProfile: PublicProfile?
    var latitude: Double?
    var longitude: Double?
    var trackerType: String = ""   // "airtag" | "tile" | "gps" | ""
    var trackerIdentifier: String = ""  // name or serial for reference

    var hasLocation: Bool { latitude != nil && longitude != nil }

    var isLoaned: Bool { currentLoan != nil }
    var qrContent: String { "\(itemFoundBaseURL)?id=\(id.uuidString)" }

    var warrantyStatus: WarrantyStatus {
        guard let exp = warrantyExpiresAt else { return .none }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        if days < 0 { return .expired }
        if days <= 30 { return .expiringSoon }
        return .valid
    }
    enum WarrantyStatus { case none, valid, expiringSoon, expired }

    var categoryIcon: String {
        switch category {
        case "tools":       return "wrench.and.screwdriver.fill"
        case "garden":      return "leaf.fill"
        case "outdoor":     return "sun.max.fill"
        case "appliances":  return "washer.fill"
        case "electronics": return "tv.fill"
        case "furniture":   return "sofa.fill"
        case "vehicles":    return "car.fill"
        case "sports":      return "figure.run"
        case "security":    return "lock.shield.fill"
        default:            return "cube.fill"
        }
    }

    var categoryColor: Color {
        switch category {
        case "tools":       return .orange
        case "garden":      return Color(red: 0.2, green: 0.8, blue: 0.3)
        case "outdoor":     return .yellow
        case "appliances":  return .blue
        case "electronics": return .purple
        case "furniture":   return Color(red: 0.7, green: 0.5, blue: 0.3)
        case "vehicles":    return .red
        case "sports":      return .cyan
        case "security":    return Color(red: 0.3, green: 0.85, blue: 0.5)
        default:            return .gray
        }
    }
}

// MARK: - Service

@MainActor
final class InventoryService: ObservableObject {
    @Published var items: [InventoryItem] = []
    private let key = "prvio.inventory.v2"

    init() { load() }

    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([InventoryItem].self, from: d) {
            items = decoded
        }
    }

    func add(_ item: InventoryItem) { items.insert(item, at: 0); save() }

    func delete(_ item: InventoryItem) {
        cancelLoanNotifications(for: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func update(_ item: InventoryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item; save() }
    }

    func loanOut(_ item: InventoryItem, to borrower: String, expectedReturn: Date?) {
        var updated = item
        let record = LoanRecord(borrowerName: borrower, loanedAt: Date(), expectedReturnDate: expectedReturn)
        updated.currentLoan = record
        update(updated)
        scheduleLoanReminders(for: updated, loan: record)
    }

    func markReturned(_ item: InventoryItem) {
        var updated = item
        if var loan = updated.currentLoan {
            loan.returnedAt = Date()
            updated.loanHistory.append(loan)
            updated.currentLoan = nil
        }
        cancelLoanNotifications(for: item)
        update(updated)
    }

    func itemByQR(_ qrString: String) -> InventoryItem? {
        // Web URL format: ...?id={uuid}
        if let url = URL(string: qrString),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idStr = comps.queryItems?.first(where: { $0.name == "id" })?.value,
           let uuid = UUID(uuidString: idStr) {
            return items.first { $0.id == uuid }
        }
        // Legacy app URL: prvio://inventory/{uuid}
        let prefix = "prvio://inventory/"
        if qrString.hasPrefix(prefix),
           let uuid = UUID(uuidString: String(qrString.dropFirst(prefix.count))) {
            return items.first { $0.id == uuid }
        }
        return nil
    }

    func syncPublicProfile(for item: InventoryItem) async {
        guard let profile = item.publicProfile, profile.isEnabled else {
            await removePublicProfile(for: item); return
        }
        struct Payload: Encodable {
            let item_uuid, item_name, owner_name, owner_phone, owner_address, property_name, user_id: String
        }
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        let p = Payload(item_uuid: item.id.uuidString, item_name: item.name,
                        owner_name: profile.ownerName, owner_phone: profile.ownerPhone,
                        owner_address: profile.ownerAddress, property_name: profile.propertyName,
                        user_id: uid.uuidString)
        try? await supabase.from("public_items").upsert(p, onConflict: "item_uuid").execute()
    }

    func removePublicProfile(for item: InventoryItem) async {
        try? await supabase.from("public_items").delete().eq("item_uuid", value: item.id.uuidString).execute()
    }

    var totalValue: Double { items.reduce(0) { $0 + $1.purchasePrice } }
    var loanedCount: Int { items.filter { $0.isLoaned }.count }
    var expiringWarrantyCount: Int { items.filter { $0.warrantyStatus == .expiringSoon }.count }

    private func save() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }

    private func scheduleLoanReminders(for item: InventoryItem, loan: LoanRecord) {
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.inventoryLoans) else { return }
        let center = UNUserNotificationCenter.current()
        let intervals: [(Int, String)] = [
            (1,  "Reminder: \(loan.borrowerName) still has your \"\(item.name)\"."),
            (3,  "3 days — \"\(item.name)\" not yet returned by \(loan.borrowerName)."),
            (7,  "1 week since \"\(item.name)\" was loaned to \(loan.borrowerName)."),
            (14, "2 weeks — \"\(item.name)\" still with \(loan.borrowerName)."),
            (30, "1 month! Ask \(loan.borrowerName) about \"\(item.name)\"."),
            (90, "3 months! \"\(item.name)\" loaned to \(loan.borrowerName) — still waiting?")
        ]
        for (days, body) in intervals {
            let content = UNMutableNotificationContent()
            content.title = "Item Not Returned"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "inventory.loan.\(item.id.uuidString).\(days)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(days) * 86400, repeats: false)
            )
            center.add(request)
        }
    }

    private func cancelLoanNotifications(for item: InventoryItem) {
        let ids = [1, 3, 7, 14, 30, 90].map { "inventory.loan.\(item.id.uuidString).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @StateObject private var service = InventoryService()
    @Environment(\.dismiss) private var dismiss
    @State private var filter: InvFilter = .all
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false

    enum InvFilter: String, CaseIterable {
        case all = "All", loaned = "Loaned", tools = "Tools"
        case garden = "Garden", outdoor = "Outdoor", electronics = "Electronics", other = "Other"

        var icon: String {
            switch self {
            case .all:         return "square.grid.2x2.fill"
            case .loaned:      return "arrow.uturn.right.circle.fill"
            case .tools:       return "wrench.and.screwdriver.fill"
            case .garden:      return "leaf.fill"
            case .outdoor:     return "sun.max.fill"
            case .electronics: return "tv.fill"
            case .other:       return "cube.fill"
            }
        }
    }

    private var filtered: [InventoryItem] {
        switch filter {
        case .all:         return service.items
        case .loaned:      return service.items.filter { $0.isLoaned }
        case .tools:       return service.items.filter { $0.category == "tools" }
        case .garden:      return service.items.filter { $0.category == "garden" }
        case .outdoor:     return service.items.filter { ["outdoor","sports","vehicles"].contains($0.category) }
        case .electronics: return service.items.filter { $0.category == "electronics" }
        case .other:       return service.items.filter { !["tools","garden","outdoor","sports","vehicles","electronics"].contains($0.category) }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !service.items.isEmpty {
                    summaryBar.padding(.horizontal, 20).padding(.vertical, 10)
                }

                if service.items.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    VStack { Spacer(); Text("No items in this category").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.4)); Spacer() }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in
                                InventoryRow(item: item)
                                    .onTapGesture { selectedItem = item }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { HapticFeedback.warning(); service.delete(item) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); service.markReturned(item) } label: { Label("Returned", systemImage: "checkmark.circle") }
                                                .tint(Color(red: 0.2, green: 0.78, blue: 0.45))
                                        } else {
                                            Button { HapticFeedback.impact(.medium); selectedItem = item } label: { Label("Loan Out", systemImage: "arrow.uturn.right.circle") }
                                                .tint(.accentColor)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 110)
                    }
                }
            }

            FloatingSpeedDial(
                actions: appSettings.fabVisible(.inventory) ? appSettings.fabActions(.inventory) : [],
                onSelect: { action in
                    switch action {
                    case .scan:    showScanner = true
                    case .addItem: showAdd = true
                    default:       router.perform(action)
                    }
                },
                bottomPadding: 100
            )
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(InvFilter.allCases, id: \.self) { f in
                            Button {
                                withAnimation(.spring(response: 0.25)) { filter = f }
                            } label: {
                                Label(
                                    "\(f.rawValue)  (\(countFor(f)))",
                                    systemImage: filter == f ? "checkmark" : f.icon
                                )
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease" : filter.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddInventorySheet { service.add($0) } }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { qrValue in
                showScanner = false
                if let found = service.itemByQR(qrValue) {
                    HapticFeedback.success()
                    selectedItem = found
                } else {
                    HapticFeedback.error()
                    scannedUnknown = true
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, service: service)
        }
        .alert("Item not found", isPresented: $scannedUnknown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This QR code doesn't match any item in your inventory.")
        }
        .onAppear {
            if autoScan && !didAutoScan {
                didAutoScan = true
                showScanner = true
            }
            if autoAdd && !didAutoAdd {
                didAutoAdd = true
                showAdd = true
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 8) {
            infoTile("€\(Int(service.totalValue))", "Value")
            infoTile("\(service.items.count)", "Items")
            infoTile("\(service.loanedCount)", "Loaned", highlight: service.loanedCount > 0)
            infoTile("\(service.expiringWarrantyCount)", "Warranty !", highlight: service.expiringWarrantyCount > 0)
        }
    }

    private func infoTile(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        GlassCard(padding: 10) {
            VStack(spacing: 3) {
                Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(highlight ? .orange : .white).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.system(size: 9)).foregroundStyle(Color.primary.opacity(0.4))
            }.frame(maxWidth: .infinity)
        }
    }

    private func countFor(_ f: InvFilter) -> Int {
        switch f {
        case .all:         return service.items.count
        case .loaned:      return service.items.filter { $0.isLoaned }.count
        case .tools:       return service.items.filter { $0.category == "tools" }.count
        case .garden:      return service.items.filter { $0.category == "garden" }.count
        case .outdoor:     return service.items.filter { ["outdoor","sports","vehicles"].contains($0.category) }.count
        case .electronics: return service.items.filter { $0.category == "electronics" }.count
        case .other:       return service.items.filter { !["tools","garden","outdoor","sports","vehicles","electronics"].contains($0.category) }.count
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No inventory yet").font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.5))
            Button("Add first item") { showAdd = true }.font(.system(size: 14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: item.categoryIcon, color: item.categoryColor, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 5) {
                        if !item.brand.isEmpty {
                            Text(item.brand).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                            Text("·").foregroundStyle(Color.primary.opacity(0.2))
                        }
                        Text(item.location.capitalized).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    if item.isLoaned, let loan = item.currentLoan {
                        Label("Loaned to \(loan.borrowerName) · \(loan.daysOut)d", systemImage: "person.fill")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.purchasePrice > 0 {
                        Text("€\(Int(item.purchasePrice))").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
                    }
                    switch item.warrantyStatus {
                    case .expiringSoon: Image(systemName: "exclamationmark.shield.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    case .expired:     Image(systemName: "xmark.shield.fill").font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    default: EmptyView()
                    }
                }
            }
        }
        .overlay {
            if item.isLoaned {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.orange.opacity(0.4), lineWidth: 1.5)
            }
        }
    }
}

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
                if !live.brand.isEmpty       { dRow("building.2.fill", "Brand",      live.brand);       rowDiv }
                if !live.serialNumber.isEmpty { dRow("number", "Serial",              live.serialNumber); rowDiv }
                if live.purchasePrice > 0    { dRow("eurosign.circle.fill", "Value",  "€\(Int(live.purchasePrice))"); rowDiv }
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
        case .valid: return "checkmark.shield.fill"
        case .expiringSoon: return "exclamationmark.shield.fill"
        case .expired: return "xmark.shield.fill"
        case .none: return "shield.slash.fill"
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
        case .valid: return Color(red: 0.3, green: 0.85, blue: 0.5)
        case .expiringSoon: return .orange
        case .expired: return .red
        case .none: return Color.primary.opacity(0.35)
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
                    if live.hasLocation {
                        Text("📍").font(.system(size: 14))
                    }
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
                        if !p.ownerName.isEmpty    { publicRow("person.fill",     p.ownerName) }
                        if !p.ownerPhone.isEmpty   { publicRow("phone.fill",      p.ownerPhone) }
                        if !p.ownerAddress.isEmpty { publicRow("house.fill",      p.ownerAddress) }
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

// MARK: - QR Code Image

struct QRCodeImage: View {
    let content: String
    var size: CGFloat = 200

    private var image: UIImage? {
        guard let data = content.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        if let img = image {
            Image(uiImage: img)
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: size, height: size)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)).frame(width: size, height: size)
        }
    }
}

// MARK: - QR Scanner

private struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if DataScannerViewController.isSupported {
                DataScannerRepresentable(onScan: onScan).ignoresSafeArea()
            } else {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.25))
                    Text("Camera scanner not available on this device").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.5)).multilineTextAlignment(.center)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 30))
                            .foregroundStyle(Color.primary.opacity(0.85)).background(Color.black.opacity(0.3), in: Circle())
                    }.padding(20)
                }
                Spacer()
                Text("Point at an item's QR code")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 60)
            }
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var fired = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let value = b.payloadStringValue {
                    fired = true
                    dataScanner.stopScanning()
                    DispatchQueue.main.async { self.onScan(value) }
                    return
                }
            }
        }
    }
}

// MARK: - Add Item Sheet

private struct AddInventorySheet: View {
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "tools"
    @State private var location = "garage"
    @State private var brand = ""
    @State private var serial = ""
    @State private var condition = "good"
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var price = ""
    @State private var hasWarranty = false
    @State private var warrantyDate = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    @State private var notes = ""

    private let categories = ["tools","garden","outdoor","appliances","electronics","furniture","vehicles","sports","security","other"]
    private let locations = ["garage","garden","basement","attic","shed","balcony","kitchen","living room","bedroom","storage"]
    private let conditions = ["excellent","good","fair","poor"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        card {
                            field("tag.fill", "Item name *", $name)
                            div
                            picker("folder.fill", "Category", $category, categories)
                            div
                            picker("mappin.circle.fill", "Location", $location, locations)
                            div
                            picker("sparkles", "Condition", $condition, conditions)
                        }
                        card {
                            field("building.2.fill", "Brand", $brand)
                            div
                            field("number", "Serial Number", $serial)
                            div
                            field("eurosign.circle.fill", "Value (€)", $price, keyboard: .decimalPad)
                        }
                        card {
                            toggle("calendar", "Purchase Date", $hasPurchaseDate)
                            if hasPurchaseDate {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("", selection: $purchaseDate, in: ...Date(), displayedComponents: .date).tint(.accentColor)
                                }.padding(.horizontal, 16).padding(.vertical, 6)
                            }
                            div
                            toggle("checkmark.shield.fill", "Has Warranty", $hasWarranty)
                            if hasWarranty {
                                div
                                HStack(spacing: 12) {
                                    Color.clear.frame(width: 28)
                                    DatePicker("Until", selection: $warrantyDate, displayedComponents: .date).tint(.accentColor).font(.system(size: 15)).foregroundStyle(.primary)
                                }.padding(.horizontal, 16).padding(.vertical, 6)
                            }
                        }
                        card {
                            HStack(spacing: 12) {
                                Image(systemName: "note.text").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                TextField("Notes (optional)", text: $notes, axis: .vertical)
                                    .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).lineLimit(3...5)
                            }.padding(.horizontal, 16).padding(.vertical, 13)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var item = InventoryItem(name: name)
                        item.category = category; item.location = location; item.brand = brand
                        item.serialNumber = serial; item.condition = condition
                        item.purchaseDate = hasPurchaseDate ? purchaseDate : nil
                        item.purchasePrice = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
                        item.warrantyExpiresAt = hasWarranty ? warrantyDate : nil
                        item.notes = notes
                        onSave(item); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
    private func field(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private func picker(_ icon: String, _ label: String, _ b: Binding<String>, _ opts: [String]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Picker("", selection: b) { ForEach(opts, id: \.self) { Text($0.capitalized).tag($0) } }.tint(Color.primary.opacity(0.5))
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    private func toggle(_ icon: String, _ label: String, _ b: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: b).tint(.accentColor).labelsHidden()
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}


// MARK: - Map pin model

struct InventoryMapPin: Identifiable {
    let id = UUID()
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

// MARK: - Location + Tracker sheet

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
