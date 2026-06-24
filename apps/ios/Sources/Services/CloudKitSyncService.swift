import Foundation
import CloudKit
import Combine

@MainActor
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var error: String?

    private let container = CKContainer(identifier: "iCloud.com.prvio.app")
    var privateDB: CKDatabase { container.privateCloudDatabase }
    var sharedDB: CKDatabase { container.sharedCloudDatabase }

    private init() {
        Task { await checkAccountStatus() }
    }

    func checkAccountStatus() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var isAvailable: Bool { accountStatus == .available }

    // MARK: - Backup a record

    func save(_ record: CKRecord) async throws {
        isSyncing = true
        defer { isSyncing = false }
        try await privateDB.save(record)
        lastSyncDate = Date()
    }

    func fetch(recordType: String, predicate: NSPredicate = NSPredicate(value: true)) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let (results, _) = try await privateDB.records(matching: query)
        return results.compactMap { try? $0.1.get() }
    }

    func delete(recordID: CKRecord.ID) async throws {
        try await privateDB.deleteRecord(withID: recordID)
    }

    // MARK: - iCloud KV Store (lightweight sync)

    func setKV(_ value: Any, forKey key: String) {
        NSUbiquitousKeyValueStore.default.set(value, forKey: key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func kv<T>(forKey key: String) -> T? {
        NSUbiquitousKeyValueStore.default.object(forKey: key) as? T
    }

    // MARK: - Sharing (Extended Share Access)

    func share(_ record: CKRecord, title: String) async throws -> CKShare {
        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .readOnly
        let (saved, _, _) = try await privateDB.modifyRecords(saving: [record, share], deleting: [])
        return saved.compactMap { $0.value as? CKShare }.first ?? share
    }
}
