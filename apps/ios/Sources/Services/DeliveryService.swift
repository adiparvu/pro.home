import Foundation

@MainActor
final class DeliveryService: ObservableObject {
    @Published var deliveries: [Delivery] = []

    private let key = "prvio.deliveries"

    init() { load() }

    // MARK: Computed

    var activeDeliveries: [Delivery] { deliveries.filter { $0.isActive } }
    var todayDeliveries: [Delivery] {
        let today = DateFormatter(); today.dateFormat = "yyyy-MM-dd"
        let todayStr = today.string(from: Date())
        return deliveries.filter { $0.expectedDate == todayStr && $0.isActive }
    }

    // MARK: CRUD

    func add(_ delivery: Delivery) {
        deliveries.insert(delivery, at: 0)
        persist()
    }

    func update(_ delivery: Delivery) {
        if let i = deliveries.firstIndex(where: { $0.id == delivery.id }) {
            deliveries[i] = delivery
            persist()
        }
    }

    func delete(_ delivery: Delivery) {
        deliveries.removeAll { $0.id == delivery.id }
        persist()
    }

    func markDelivered(_ delivery: Delivery) {
        var updated = delivery
        updated.status = "delivered"
        update(updated)
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Delivery].self, from: data) else { return }
        deliveries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(deliveries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
