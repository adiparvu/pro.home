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
        // One-round-trip startup (migration 164): if the orchestration's
        // single `app_bootstrap` RPC already delivered this table's slice
        // for this property — under the exact same scope/order/limit — the
        // fetch decodes it locally instead of paying another trip. Any
        // mismatch (parameters, decode, staleness, already consumed) falls
        // straight through to the classic network path below.
        if let data = consumeBootstrapSlice(table: table, propertyId: propertyId,
                                            scope: scope, order: order,
                                            ascending: ascending, limit: limit),
           let rows = try? bootstrapDecoder.decode([T].self, from: data) {
            return rows
        }
        // A request riding a missing/expired session gets the anon key, and
        // under RLS that is a SUCCESSFUL response with ZERO rows — which the
        // services then honestly adopt and persist, poisoning every cache
        // with [] (the "inventory disappears after each update" field
        // report: first launch after an update fetches before the token
        // refresh landed). Refresh-or-throw first: a thrown session error is
        // a normal load failure (cache kept), and a response that does
        // arrive is guaranteed to carry the user's claims — so an empty
        // list is a REAL empty list, never an auth artifact.
        _ = try await supabase.auth.session
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

    // MARK: - Bootstrap (one round-trip world load, migration 164)
    //
    // Startup used to pay a full round-trip PER TABLE (~13 trips at
    // 50-70ms each to eu-west-1). The orchestration now calls
    // `preloadBootstrap` ONCE: a single `app_bootstrap` RPC (SECURITY
    // INVOKER — RLS applies to the caller exactly as in the per-table
    // path) returns every startup table in one body, each slice as the
    // TEXT of its jsonb array so the client decodes the exact bytes
    // Postgres produced (no numeric re-serialization drift on Decimal
    // money). Slices are single-use and parameter-checked; a failed RPC
    // costs nothing — the cache stays empty and startup degrades to the
    // classic fan-out.

    struct BootstrapSpec { let scope: Scope; let order: String; let ascending: Bool; let limit: Int }

    /// Mirrored VERBATIM by the `app_bootstrap` SQL (migration 164). A
    /// table's spec must match the service's fetch call, or its slice can
    /// never be consumed and that service simply pays the classic trip.
    static let bootstrapSpecs: [String: BootstrapSpec] = [
        "maintenance_tasks":     .init(scope: .orNull, order: "created_at", ascending: false, limit: 500),
        "plants":                .init(scope: .strict, order: "created_at", ascending: true,  limit: 500),
        "supply_lists":          .init(scope: .strict, order: "created_at", ascending: true,  limit: 500),
        "supply_items":          .init(scope: .strict, order: "created_at", ascending: true,  limit: 1000),
        "pantry_items":          .init(scope: .strict, order: "created_at", ascending: true,  limit: 500),
        "packages":              .init(scope: .strict, order: "created_at", ascending: false, limit: 500),
        "documents":             .init(scope: .orNull, order: "created_at", ascending: false, limit: 500),
        "financial_records":     .init(scope: .orNull, order: "date",       ascending: false, limit: 1000),
        "appliances":            .init(scope: .strict, order: "created_at", ascending: true,  limit: 500),
        "calendar_events":       .init(scope: .strict, order: "starts_at",  ascending: true,  limit: 1000),
        "inventory_items":       .init(scope: .strict, order: "created_at", ascending: false, limit: 1000),
        "family_members":        .init(scope: .orNull, order: "created_at", ascending: true,  limit: 500),
        "photo_journal_entries": .init(scope: .strict, order: "taken_at",   ascending: false, limit: 600),
    ]

    /// Wire timestamps decode through the one date authority (P0-A); a
    /// plain `yyyy-MM-dd` date column parses through the day formatter.
    private static let bootstrapDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = ISODate.date(from: s) ?? AppDate.day(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unparseable wire date: \(s)"))
        }
        return d
    }()

    private static let bootstrapLock = NSLock()
    nonisolated(unsafe) private static var bootstrapSlices: [String: Data] = [:]
    nonisolated(unsafe) private static var bootstrapPropertyId: UUID?
    nonisolated(unsafe) private static var bootstrapLoadedAt: Date?

    /// Fetch the whole startup world in one round-trip. Failure is free:
    /// the slice cache stays empty and every service load goes to the
    /// network exactly as before.
    static func preloadBootstrap(propertyId: UUID) async {
        struct Params: Encodable { let p_property_id: UUID }
        do {
            // Same session guard as fetch: an anon-keyed RPC would return
            // thirteen honest-looking empty slices.
            _ = try await supabase.auth.session
            let data = try await supabase
                .rpc("app_bootstrap", params: Params(p_property_id: propertyId))
                .execute()
                .data
            let slices = try JSONDecoder().decode([String: String].self, from: data)
            bootstrapLock.lock()
            bootstrapSlices = slices
                .filter { bootstrapSpecs[$0.key] != nil }
                .mapValues { Data($0.utf8) }
            bootstrapPropertyId = propertyId
            bootstrapLoadedAt = Date()
            bootstrapLock.unlock()
        } catch {
            // Classic fan-out takes over — never louder than a log.
            print("bootstrap: RPC unavailable, classic loads (\(error))")
        }
    }

    /// Single-use, parameter-checked slice take. 30s validity: a slice is
    /// only ever meant for the load burst right after its preload.
    private static func consumeBootstrapSlice(table: String, propertyId: UUID?,
                                              scope: Scope, order: String,
                                              ascending: Bool, limit: Int) -> Data? {
        guard let spec = bootstrapSpecs[table],
              spec.scope == scope, spec.order == order,
              spec.ascending == ascending, spec.limit == limit else { return nil }
        bootstrapLock.lock()
        defer { bootstrapLock.unlock() }
        guard let pid = propertyId, pid == bootstrapPropertyId,
              let loadedAt = bootstrapLoadedAt,
              Date().timeIntervalSince(loadedAt) < 30 else { return nil }
        return bootstrapSlices.removeValue(forKey: table)
    }
}
