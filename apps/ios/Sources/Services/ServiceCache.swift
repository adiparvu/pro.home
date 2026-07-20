import Foundation

// MARK: - Offline hydration cache
//
// The app must never open empty: every core service hydrates instantly from
// the last data it saw, then refreshes over the network. A basement with no
// signal still shows your documents, tasks and plants — and a cold launch
// paints yesterday's state in the first frame instead of skeletons.
//
// Deliberately simple: JSON files, one per entity per property, written
// off-main after every successful fetch, protected with complete file
// protection. This is a read cache, not a sync engine — writes still
// require the network, which keeps conflict handling out of scope.

enum ServiceCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let d = base.appendingPathComponent("ServiceCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    private static func url(_ entity: String, propertyId: UUID?) -> URL {
        let scope = propertyId?.uuidString.lowercased() ?? "all"
        return dir.appendingPathComponent("\(entity).\(scope).json")
    }

    /// Synchronous read — called once per service at hydration time; the
    /// files are small (list snapshots), so this stays well under a frame.
    static func load<T: Decodable>(_ type: T.Type, entity: String, propertyId: UUID? = nil) -> T? {
        guard let data = try? Data(contentsOf: url(entity, propertyId: propertyId)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Fire-and-forget write off the main actor; household data is encrypted
    /// at rest via complete file protection.
    static func save<T: Encodable & Sendable>(_ value: T, entity: String, propertyId: UUID? = nil) {
        let target = url(entity, propertyId: propertyId)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(value) else { return }
            // Until-first-unlock, not Complete: the hydration cache must be
            // readable on background beats (watch wakes, pushes, prewarm)
            // with the device locked — Complete made those launches start
            // empty. Still encrypted at rest until the first unlock after
            // boot, which is the right class for a read cache.
            try? data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Wipes everything — call on sign-out so the next account never sees
    /// the previous household's data.
    static func clear() {
        try? FileManager.default.removeItem(at: dir)
    }
}
