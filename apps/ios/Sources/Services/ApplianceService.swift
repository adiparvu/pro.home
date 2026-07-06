import Foundation
import Observation

@MainActor
@Observable
final class ApplianceService {
    var appliances: [Appliance] = []
    var isLoading = false
    var error: String?

    var appliancesExpiringWarranty: [Appliance] {
        appliances.filter { $0.isWarrantyExpiringSoon || $0.isWarrantyExpired }
    }

    var byCategory: [ApplianceCategory: [Appliance]] {
        Dictionary(grouping: appliances, by: { $0.category })
    }

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if appliances.isEmpty, let cached = ServiceCache.load([Appliance].self, entity: "appliances", propertyId: propertyId) {
            appliances = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            appliances = try await supabase
                .from("appliances")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            ServiceCache.save(appliances, entity: "appliances", propertyId: propertyId)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func add(_ payload: NewAppliancePayload) async {
        do {
            let inserted: Appliance = try await supabase
                .from("appliances")
                .insert(payload)
                .select().single().execute().value
            appliances.append(inserted)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ appliance: Appliance) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let upd = ApplianceUpdate(
            name: appliance.name,
            brand: appliance.brand,
            modelNumber: appliance.modelNumber,
            serialNumber: appliance.serialNumber,
            location: appliance.location,
            category: appliance.category.rawValue,
            purchaseDate: appliance.purchaseDate,
            warrantyUntil: appliance.warrantyUntil,
            purchasePrice: appliance.purchasePrice,
            notes: appliance.notes,
            photoUrl: appliance.photoUrl,
            updatedAt: now
        )
        do {
            let updated: Appliance = try await supabase
                .from("appliances").update(upd)
                .eq("id", value: appliance.id.uuidString)
                .select().single().execute().value
            if let i = appliances.firstIndex(where: { $0.id == appliance.id }) {
                appliances[i] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ appliance: Appliance) async {
        appliances.removeAll { $0.id == appliance.id }
        do {
            try await supabase
                .from("appliances").delete()
                .eq("id", value: appliance.id.uuidString).execute()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
