import Foundation
import UserNotifications

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
        if let url = URL(string: qrString),
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let idStr = comps.queryItems?.first(where: { $0.name == "id" })?.value,
           let uuid = UUID(uuidString: idStr) {
            return items.first { $0.id == uuid }
        }
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

    // MARK: - Private

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
