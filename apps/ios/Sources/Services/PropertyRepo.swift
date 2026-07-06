import Foundation

// MARK: - The one fetch skeleton for property-scoped tables
//
// Twenty-plus services used to hand-copy the same load body: build the
// query, scope it to the active property, order, limit, decode. Besides
// the duplication, every one of those decodes ran on the main actor —
// a full-table JSON decode on the UI thread per service, per refresh.
//
// `PropertyRepo.fetch` is deliberately *nonisolated*: callers await it
// from `@MainActor` services, the network + decode run on the cooperative
// pool, and only the array assignment hops back to the UI.

enum PropertyRepo {
    enum Scope {
        /// `property_id = pid OR property_id IS NULL` — the app's default:
        /// legacy rows without a property stay visible rather than silently
        /// disappearing.
        case orNull
        /// `property_id = pid` strictly.
        case strict
    }

    static func fetch<T: Decodable & Sendable>(
        table: String,
        propertyId: UUID?,
        scope: Scope = .orNull,
        order: String = "created_at",
        ascending: Bool = false,
        limit: Int
    ) async throws -> [T] {
        var query = supabase.from(table).select()
        if let pid = propertyId {
            switch scope {
            case .orNull:
                query = query.or("property_id.eq.\(pid.uuidString),property_id.is.null")
            case .strict:
                query = query.eq("property_id", value: pid.uuidString)
            }
        }
        return try await query
            .order(order, ascending: ascending)
            .limit(limit)   // explicit cap — PostgREST truncates silently without one
            .execute()
            .value
    }
}
