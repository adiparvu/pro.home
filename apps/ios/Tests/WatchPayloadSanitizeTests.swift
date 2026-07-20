import XCTest
@testable import PRVIO

// Unit tests for WatchPayload.sanitizedForRender() — the render-safe copy
// pushed to the wrist. Duplicate ids in any id-keyed collection are undefined
// behavior in a watch List/ForEach (crash at first render, reproduced on
// EVERY launch because the payload is cached), so sanitize must dedupe every
// collection, first occurrence wins, and be a no-op on clean payloads.
//
// Also pins the decoding contract: a payload JSON written by an OLD build —
// carrying only the original fields — must decode in every process, with the
// newer collections empty (a poisoned/partial cache must never brick the
// watch app). Run with Cmd+U (PRVIOTests scheme).
final class WatchPayloadSanitizeTests: XCTestCase {

    // MARK: - Entry builders (memberwise, defaults for the optional tails)

    private func task(_ id: UUID, _ title: String = "task") -> TaskCatalogEntry {
        TaskCatalogEntry(id: id, title: title, priority: "normal", isCompleted: false)
    }
    private func plant(_ id: UUID, _ name: String = "plant") -> PlantCatalogEntry {
        PlantCatalogEntry(id: id, name: name, emoji: "🌱", needsWatering: false)
    }
    private func supply(_ id: UUID, _ name: String = "supply") -> SupplyCatalogEntry {
        SupplyCatalogEntry(id: id, name: name, isCompleted: false)
    }
    private func delivery(_ id: UUID, _ title: String = "package") -> DeliveryCatalogEntry {
        DeliveryCatalogEntry(id: id, title: title, carrier: nil, status: "expected", eta: nil)
    }
    private func pantry(_ id: UUID, _ name: String = "jar") -> PantryCatalogEntry {
        PantryCatalogEntry(id: id, name: name, quantity: 1, unit: "pcs")
    }
    private func sensor(_ id: UUID, _ name: String = "sensor") -> SensorCatalogEntry {
        SensorCatalogEntry(id: id, name: name, icon: "thermometer",
                           displayValue: "21 °C", zone: nil,
                           isAlerting: false, isCritical: false)
    }
    private func actuator(_ id: UUID, _ name: String = "relay") -> ActuatorCatalogEntry {
        ActuatorCatalogEntry(id: id, name: name, kind: "relay", isOn: false,
                             commands: ["on", "off"])
    }
    private func contact(_ id: UUID, _ name: String = "contact") -> EmergencyContactEntry {
        EmergencyContactEntry(id: id, name: name, role: "plumber", phone: "0700000000")
    }
    private func step(_ id: UUID, _ title: String = "step") -> EmergencyStepEntry {
        EmergencyStepEntry(id: id, title: title, detail: "turn the valve")
    }
    private func dm(_ id: UUID, _ peer: String = "peer") -> DMConversationEntry {
        DMConversationEntry(id: id, peerName: peer)
    }

    // MARK: - Dedupe: first occurrence wins

    func testDedupeKeepsFirstOccurrenceAndOrder() {
        let dup = UUID(), other = UUID()
        var p = WatchPayload(snapshot: PRVIOWidgetSnapshot())
        p.tasks = [task(dup, "first"), task(dup, "second"), task(other, "third")]

        let s = p.sanitizedForRender()
        XCTAssertEqual(s.tasks.count, 2)
        XCTAssertEqual(s.tasks.map(\.title), ["first", "third"],
                       "dedupe must keep the FIRST occurrence and preserve order")
    }

    func testDedupeCoversEveryCollection() {
        var p = WatchPayload(snapshot: PRVIOWidgetSnapshot())
        let id = (0..<10).map { _ in UUID() }
        p.tasks             = [task(id[0], "keep"),     task(id[0], "drop")]
        p.plants            = [plant(id[1], "keep"),    plant(id[1], "drop")]
        p.supplies          = [supply(id[2], "keep"),   supply(id[2], "drop")]
        p.deliveries        = [delivery(id[3], "keep"), delivery(id[3], "drop")]
        p.pantry            = [pantry(id[4], "keep"),   pantry(id[4], "drop")]
        p.sensors           = [sensor(id[5], "keep"),   sensor(id[5], "drop")]
        p.actuators         = [actuator(id[6], "keep"), actuator(id[6], "drop")]
        p.emergencyContacts = [contact(id[7], "keep"),  contact(id[7], "drop")]
        p.emergencySteps    = [step(id[8], "keep"),     step(id[8], "drop")]
        p.dmConversations   = [dm(id[9], "keep"),       dm(id[9], "drop")]

        let s = p.sanitizedForRender()
        XCTAssertEqual(s.tasks.map(\.title),                ["keep"])
        XCTAssertEqual(s.plants.map(\.name),                ["keep"])
        XCTAssertEqual(s.supplies.map(\.name),              ["keep"])
        XCTAssertEqual(s.deliveries.map(\.title),           ["keep"])
        XCTAssertEqual(s.pantry.map(\.name),                ["keep"])
        XCTAssertEqual(s.sensors.map(\.name),               ["keep"])
        XCTAssertEqual(s.actuators.map(\.name),             ["keep"])
        XCTAssertEqual(s.emergencyContacts.map(\.name),     ["keep"])
        XCTAssertEqual(s.emergencySteps.map(\.title),       ["keep"])
        XCTAssertEqual(s.dmConversations.map(\.peerName),   ["keep"])
    }

    // MARK: - Clean payload is untouched (idempotent)

    func testSanitizeIsIdentityOnCleanPayload() throws {
        var p = WatchPayload(snapshot: PRVIOWidgetSnapshot())
        p.accountId = "user-1"
        p.tasks             = [task(UUID(), "a"), task(UUID(), "b")]
        p.plants            = [plant(UUID())]
        p.supplies          = [supply(UUID())]
        p.deliveries        = [delivery(UUID())]
        p.pantry            = [pantry(UUID())]
        p.sensors           = [sensor(UUID())]
        p.actuators         = [actuator(UUID())]
        p.emergencyContacts = [contact(UUID())]
        p.emergencySteps    = [step(UUID())]
        p.dmConversations   = [dm(UUID())]
        p.pageOrder = ["tasks", "plants"]

        // WatchPayload isn't Equatable — compare stable JSON encodings.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(p)

        let once = p.sanitizedForRender()
        XCTAssertEqual(try encoder.encode(once), original,
                       "sanitize must not change an already-clean payload")

        let twice = once.sanitizedForRender()
        XCTAssertEqual(try encoder.encode(twice), original,
                       "sanitize must be idempotent")
    }

    // MARK: - Decoding contract: old payload JSON (no new fields) must decode

    func testDecodingPayloadWithoutNewFieldsSucceeds() throws {
        // Exactly what a V1 build wrote: snapshot + tasks + plants, nothing
        // else. This JSON is CACHED on real wrists — if it stops decoding,
        // the watch freezes on defaults (or crash-loops) until the cache is
        // replaced.
        let json = Data("""
        {
          "snapshot": { "openTaskCount": 2, "unreadMessages": 1 },
          "tasks": [
            { "id": "0BADC0DE-0000-4000-8000-000000000001",
              "title": "Fix gutter", "priority": "high", "isCompleted": false }
          ],
          "plants": []
        }
        """.utf8)

        let p = try JSONDecoder().decode(WatchPayload.self, from: json)

        XCTAssertEqual(p.snapshot.openTaskCount, 2)
        XCTAssertEqual(p.snapshot.unreadMessages, 1)
        XCTAssertEqual(p.tasks.count, 1)
        XCTAssertEqual(p.tasks.first?.title, "Fix gutter")
        XCTAssertTrue(p.plants.isEmpty)

        // Fields added after V1 fall back to their documented defaults.
        XCTAssertNil(p.accountId)
        XCTAssertTrue(p.isFamilyScope)
        XCTAssertTrue(p.supplies.isEmpty)
        XCTAssertTrue(p.deliveries.isEmpty)
        XCTAssertTrue(p.pantry.isEmpty)
        XCTAssertTrue(p.sensors.isEmpty)
        XCTAssertTrue(p.actuators.isEmpty)
        XCTAssertTrue(p.emergencyContacts.isEmpty)
        XCTAssertTrue(p.emergencySteps.isEmpty)
        XCTAssertTrue(p.dmConversations.isEmpty)
        XCTAssertNil(p.pageOrder)
        XCTAssertNil(p.latitude)
        XCTAssertNil(p.insightTitle)
    }
}
