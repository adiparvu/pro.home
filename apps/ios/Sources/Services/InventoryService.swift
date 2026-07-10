import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class InventoryService {
    var items: [InventoryItem] = []
    var isLoading = false
    var error: String?

    private(set) var currentPropertyId: UUID?
    private(set) var currentUserId: UUID?

    init() {}

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if items.isEmpty, let cached = ServiceCache.load([InventoryItem].self, entity: "inventory", propertyId: propertyId) {
            items = cached
        }
        currentPropertyId = propertyId
        currentUserId = supabase.auth.currentSession?.user.id
        isLoading = true
        defer { isLoading = false }
        do {
            let records: [DBInventoryRecord] = try await PropertyRepo.fetch(
                table: "inventory_items", propertyId: propertyId, scope: .strict, limit: 1000)
            items = records.map { $0.toInventoryItem() }
            ServiceCache.save(items, entity: "inventory", propertyId: propertyId)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func add(_ item: InventoryItem) async {
        guard let propertyId = currentPropertyId else { return }
        do {
            let new = item.toNew(propertyId: propertyId, addedBy: currentUserId)
            let record: DBInventoryRecord = try await supabase
                .from("inventory_items")
                .insert(new)
                .select()
                .single()
                .execute()
                .value
            let saved = record.toInventoryItem()
            items.insert(saved, at: 0)
            // Photos are stored locally under the draft id; the DB assigns
            // the real id on insert, so move them over.
            InventoryImageStore.migrate(from: item.id, to: saved.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ item: InventoryItem) async {
        do {
            let record: DBInventoryRecord = try await supabase
                .from("inventory_items")
                .update(item.toUpdatePayload())
                .eq("id", value: item.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            let updated = record.toInventoryItem()
            if let i = items.firstIndex(where: { $0.id == item.id }) {
                items[i] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ item: InventoryItem) async {
        cancelLoanNotifications(for: item)
        do {
            try await supabase
                .from("inventory_items")
                .delete()
                .eq("id", value: item.id.uuidString)
                .execute()
            items.removeAll { $0.id == item.id }
            InventoryImageStore.deleteAll(for: item.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loanOut(_ item: InventoryItem, to borrower: String, expectedReturn: Date?) async {
        var updated = item
        let record = LoanRecord(borrowerName: borrower, loanedAt: Date(), expectedReturnDate: expectedReturn)
        updated.currentLoan = record
        await update(updated)
        scheduleLoanReminders(for: updated, loan: record)
    }

    func markReturned(_ item: InventoryItem) async {
        var updated = item
        if var loan = updated.currentLoan {
            loan.returnedAt = Date()
            updated.loanHistory.append(loan)
            updated.currentLoan = nil
        }
        cancelLoanNotifications(for: item)
        await update(updated)
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
        _ = try? await supabase.from("public_items").upsert(p, onConflict: "item_uuid").execute()
    }

    func removePublicProfile(for item: InventoryItem) async {
        _ = try? await supabase.from("public_items").delete().eq("item_uuid", value: item.id.uuidString).execute()
    }

    var totalValue: Double { items.reduce(0) { $0 + $1.purchasePrice } }
    var loanedCount: Int { items.filter { $0.isLoaned }.count }
    /// Items that have a warranty on record (valid, expiring or expired).
    var warrantyCount: Int { items.filter { $0.warrantyExpiresAt != nil }.count }
    var expiringWarrantyCount: Int { items.filter { $0.warrantyStatus == .expiringSoon }.count }

    // MARK: - Private

    private func scheduleLoanReminders(for item: InventoryItem, loan: LoanRecord) {
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.inventoryLoans) else { return }
        let center = UNUserNotificationCenter.current()
        let intervals: [(Int, String)] = [
            (1,  String(format: String(localized: "Reminder: %@ still has your \"%@\"."), loan.borrowerName, item.name)),
            (3,  String(format: String(localized: "3 days — \"%@\" not yet returned by %@."), item.name, loan.borrowerName)),
            (7,  String(format: String(localized: "1 week since \"%@\" was loaned to %@."), item.name, loan.borrowerName)),
            (14, String(format: String(localized: "2 weeks — \"%@\" still with %@."), item.name, loan.borrowerName)),
            (30, String(format: String(localized: "1 month! Ask %@ about \"%@\"."), loan.borrowerName, item.name)),
            (90, String(format: String(localized: "3 months! \"%@\" loaned to %@ — still waiting?"), item.name, loan.borrowerName)),
        ]
        for (days, body) in intervals {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Item Not Returned")
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
