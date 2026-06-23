import Foundation

@MainActor
final class DeliveryService: ObservableObject {
    @Published var deliveries: [Delivery] = []
    private(set) var currentPropertyId: UUID?

    // MARK: Computed

    var activeDeliveries: [Delivery] { deliveries.filter { $0.isActive } }
    var todayDeliveries: [Delivery] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        return deliveries.filter { $0.expectedDate == todayStr && $0.isActive }
    }

    // MARK: Supabase CRUD

    func load(propertyId: UUID) async {
        currentPropertyId = propertyId
        do {
            deliveries = try await supabase
                .from("packages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            #if DEBUG
            print("DeliveryService.load error:", error)
            #endif
        }
    }

    func add(_ new: NewDelivery) async {
        do {
            let result: Delivery = try await supabase
                .from("packages")
                .insert(new)
                .select()
                .single()
                .execute()
                .value
            deliveries.insert(result, at: 0)
        } catch {
            #if DEBUG
            print("DeliveryService.add error:", error)
            #endif
        }
    }

    func update(_ delivery: Delivery) async {
        do {
            let result: Delivery = try await supabase
                .from("packages")
                .update([
                    "description":      delivery.description,
                    "carrier":          delivery.carrier ?? "",
                    "tracking_number":  delivery.trackingNumber ?? "",
                    "status":           delivery.status,
                    "expected_date":    delivery.expectedDate ?? "",
                    "notes":            delivery.notes ?? "",
                ])
                .eq("id", value: delivery.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = deliveries.firstIndex(where: { $0.id == delivery.id }) {
                deliveries[i] = result
            }
        } catch {
            #if DEBUG
            print("DeliveryService.update error:", error)
            #endif
        }
    }

    func delete(_ delivery: Delivery) async {
        do {
            try await supabase
                .from("packages")
                .delete()
                .eq("id", value: delivery.id.uuidString)
                .execute()
            deliveries.removeAll { $0.id == delivery.id }
        } catch {
            #if DEBUG
            print("DeliveryService.delete error:", error)
            #endif
        }
    }

    func markDelivered(_ delivery: Delivery) async {
        var updated = delivery
        updated.status = "delivered"
        await update(updated)
    }
}
