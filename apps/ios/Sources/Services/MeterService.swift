import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

// MARK: - Meter service ("Contoare & utilități")
//
// Loads the property's index readings, records new ones (with an optional
// photo of the dial, uploaded like journal photos), and owns the monthly
// "trimite indexul" reminders — plain repeating local notifications, one per
// meter, stored per device (each member picks their own reminder day).

@MainActor
@Observable
final class MeterService {
    private(set) var readings: [MeterReading] = []
    var isLoading = false
    var error: String?
    private var loadedPropertyId: UUID?

    // MARK: - Load (lazy — first Meters surface, not app launch)

    func loadIfNeeded() async {
        let pid = PropertyService.activePropertyId
        guard loadedPropertyId != pid || readings.isEmpty else { return }
        await load()
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        if readings.isEmpty, let cached = ServiceCache.load([MeterReading].self, entity: "meters", propertyId: pid) {
            readings = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            readings = try await PropertyRepo.fetch(table: "meter_readings", propertyId: pid,
                                                    order: "reading_date", limit: 1000)
            loadedPropertyId = pid
            ServiceCache.save(readings, entity: "meters", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    func readings(for kind: MeterKind) -> [MeterReading] {
        readings.filter { $0.meterType == kind.rawValue }
    }

    func latest(for kind: MeterKind) -> MeterReading? {
        readings(for: kind).max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    // MARK: - Mutations

    private struct NewReading: Encodable {
        let propertyId: String
        let meterType: String
        let reading: Double
        let unit: String
        let readingDate: String
        let photoUrl: String?
        let notes: String?
        enum CodingKeys: String, CodingKey {
            case reading, unit, notes
            case propertyId  = "property_id"
            case meterType   = "meter_type"
            case readingDate = "reading_date"
            case photoUrl    = "photo_url"
        }
    }

    /// Records an index. The photo (a snapshot of the dial — the household's
    /// proof if the provider disputes) uploads to the same bucket/path family
    /// as journal photos before the row is written.
    func addReading(kind: MeterKind, value: Double, date: Date,
                    note: String?, photoData: Data?) async throws {
        guard let pid = PropertyService.activePropertyId else { return }
        var photoUrl: String?
        if let photoData, let uid = supabase.auth.currentSession?.user.id {
            let compressed = UIImage(data: photoData)
                .flatMap { $0.uploadJPEG(quality: 0.8) } ?? photoData
            let path = "\(uid.uuidString.lowercased())/meters/\(pid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try await supabase.storage.from("documents")
                .upload(path, data: compressed,
                        options: FileOptions(contentType: "image/jpeg", upsert: false))
            photoUrl = try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
        }
        try await supabase.from("meter_readings").insert(NewReading(
            propertyId: pid.uuidString,
            meterType: kind.rawValue,
            reading: value,
            unit: kind.defaultUnit,
            readingDate: AppDate.dayString(from: date),
            photoUrl: photoUrl,
            notes: note?.isEmpty == true ? nil : note)).execute()
        await load()
    }

    func deleteReading(_ reading: MeterReading) async {
        do {
            try await supabase.from("meter_readings")
                .delete().eq("id", value: reading.id.uuidString).execute()
            readings.removeAll { $0.id == reading.id }
        } catch { self.error = error.recordableDescription }
    }

    // MARK: - Monthly reminders ("trimite indexul") — per device

    private static func reminderKey(_ kind: MeterKind) -> String { "prvio.meterReminder.\(kind.rawValue)" }
    private static func reminderId(_ kind: MeterKind) -> String { "meter-reminder-\(kind.rawValue)" }

    /// 1…28 = day of month; 0/absent = off.
    func reminderDay(for kind: MeterKind) -> Int {
        UserDefaults.standard.integer(forKey: Self.reminderKey(kind))
    }

    func setReminderDay(_ day: Int, for kind: MeterKind) {
        UserDefaults.standard.set(day, forKey: Self.reminderKey(kind))
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderId(kind)])
        guard (1...28).contains(day) else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "meter_reminder_title")
        content.body = String(format: String(localized: "meter_reminder_body_fmt"),
                              String(localized: String.LocalizationValue(kindKey(kind))))
        content.sound = .default
        var comps = DateComponents()
        comps.day = day
        comps.hour = 9
        center.add(UNNotificationRequest(
            identifier: Self.reminderId(kind),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }

    private func kindKey(_ kind: MeterKind) -> String {
        switch kind {
        case .electricity: return "meter_electricity"
        case .gas:         return "meter_gas"
        case .water:       return "meter_water"
        case .hotWater:    return "meter_hot_water"
        }
    }
}
