// Persistence stores for the chat info screens (split from ChatInfoViews).
import SwiftUI
import UIKit
import PhotosUI
import LocalAuthentication
import AudioToolbox
import AVFoundation

// MARK: - Group description + member labels (local cache + Supabase sync)

enum GroupDescriptionStore {
    static func text() -> String { UserDefaults.standard.string(forKey: "group.description") ?? "" }
    static func set(_ t: String, propertyId: UUID? = nil) {
        UserDefaults.standard.set(t, forKey: "group.description")
        guard let pid = propertyId else { return }
        Task {
            struct P: Encodable { let property_id: String; let description: String }
            _ = try? await supabase.from("chat_group_settings")
                .upsert(P(property_id: pid.uuidString, description: t), onConflict: "property_id")
                .execute()
        }
    }
    /// Pull the shared description into the local cache.
    static func loadRemote(_ propertyId: UUID) async {
        struct Row: Decodable { let description: String? }
        guard let rows: [Row] = try? await supabase.from("chat_group_settings")
            .select("description").eq("property_id", value: propertyId.uuidString)
            .execute().value else { return }
        if let desc = rows.first?.description {
            UserDefaults.standard.set(desc, forKey: "group.description")
        }
    }
}

enum MemberLabelStore {
    static func label(_ memberId: String) -> String { UserDefaults.standard.string(forKey: "member.label.\(memberId)") ?? "" }
    static func set(_ memberId: String, _ t: String, propertyId: UUID? = nil) {
        UserDefaults.standard.set(t, forKey: "member.label.\(memberId)")
        guard let pid = propertyId else { return }
        Task {
            struct R: Encodable { let property_id: String; let member_id: String; let label: String }
            _ = try? await supabase.from("chat_member_labels")
                .upsert(R(property_id: pid.uuidString, member_id: memberId, label: t),
                        onConflict: "property_id,member_id")
                .execute()
        }
    }
    /// Pull all shared member labels for the property into the local cache.
    static func loadRemote(_ propertyId: UUID) async {
        struct Row: Decodable { let member_id: String; let label: String? }
        guard let rows: [Row] = try? await supabase.from("chat_member_labels")
            .select("member_id,label").eq("property_id", value: propertyId.uuidString)
            .execute().value else { return }
        for r in rows {
            UserDefaults.standard.set(r.label ?? "", forKey: "member.label.\(r.member_id)")
        }
    }
}

/// Reusable editor sheet for short text (group description, member label, …).
// MARK: - Group permissions

enum GroupPermissionStore {
    // Each key stores the toggle value: true = members allowed, false = only admins.
    // Defaults: members can send (true); edit info / add members are admins-only
    // (false); approve new members on (true).
    static func value(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: "group.perm.\(key)") as? Bool ?? def
    }
    static func set(_ key: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: "group.perm.\(key)") }
}

// MARK: - Clear conversation (local "Golește conversația")
//
// Stores a per-conversation cutoff timestamp; messages at/before it are hidden
// from that device's view (WhatsApp "clear chat" semantics — local only).

enum ConversationClearStore {
    private static func key(_ id: String) -> String { "chat.clearedAt.\(id)" }
    static func clearedAt(_ id: String) -> Date? {
        let t = UserDefaults.standard.double(forKey: key(id))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static func clear(_ id: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key(id))
        // Sync the cutoff so the conversation stays cleared on every device.
        Task { await ChatPrefsSync.setCleared(convId: id, propertyId: nil) }
    }
    static func reset(_ id: String) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
    /// Applies a cutoff pulled from Supabase (another device). Only advances the
    /// local cutoff forward, never backward.
    static func applyRemote(_ id: String, iso: String?) {
        guard let iso, let d = ISODate.date(from: iso) else { return }
        if d.timeIntervalSince1970 > UserDefaults.standard.double(forKey: key(id)) {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: key(id))
        }
    }
    /// Keeps only items strictly newer than the cutoff. Items without a date
    /// (date closure returns nil) are kept.
    static func filter<T>(_ items: [T], convId: String, date: (T) -> Date?) -> [T] {
        guard let cutoff = clearedAt(convId) else { return items }
        return items.filter { item in
            guard let d = date(item) else { return true }
            return d > cutoff
        }
    }
}

// MARK: - Mute store (shared with conversation list)

enum ChatMuteStore {
    static func muted() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.muted") ?? []) }
    static func isMuted(_ id: String) -> Bool { muted().contains(id) }
    static func setMuted(_ id: String, _ on: Bool) {
        var s = muted()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.muted")
    }
}

// MARK: - Per-conversation notification tones (stored preference)

enum ChatToneStore {
    static let alertTones = ["Default", "Note", "Chime", "Glass", "Bamboo", "None"]
    static let callTones  = ["Default", "Classic", "Reflection", "Radar", "None"]

    static func alertTone(_ id: String) -> String {
        UserDefaults.standard.string(forKey: "chat.alerttone.\(id)") ?? "Default"
    }
    static func setAlertTone(_ id: String, _ tone: String) {
        UserDefaults.standard.set(tone, forKey: "chat.alerttone.\(id)")
    }
    static func callTone(_ id: String) -> String {
        UserDefaults.standard.string(forKey: "chat.calltone.\(id)") ?? "Default"
    }

    /// The honest half of the preference: the tone the user picked actually
    /// plays when a message lands while the app is open. (Notifications
    /// outside the app keep the system default — iOS doesn't let apps use
    /// Apple's tones there.)
    @MainActor
    static func playIncoming(_ id: String) {
        guard UIApplication.shared.applicationState == .active,
              !ChatMuteStore.isMuted(id) else { return }
        let name = alertTone(id)
        guard name != "None" else { return }
        if let tone = SystemToneCatalog.tone(named: name, isCall: false) {
            SystemToneCatalog.play(tone)
        } else {
            ChatTonePreview.play(name, isCall: false)
        }
    }
    static func setCallTone(_ id: String, _ tone: String) {
        UserDefaults.standard.set(tone, forKey: "chat.calltone.\(id)")
    }
}

// MARK: - Block / report

enum ChatBlockStore {
    static func blocked() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.blocked") ?? []) }
    static func isBlocked(_ id: String) -> Bool { blocked().contains(id) }
    static func setBlocked(_ id: String, _ on: Bool) {
        var s = blocked()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.blocked")
    }
    static func report(_ id: String) {
        var s = Set(UserDefaults.standard.stringArray(forKey: "chat.reported") ?? [])
        s.insert(id)
        UserDefaults.standard.set(Array(s), forKey: "chat.reported")
    }
}

/// Builds a plain-text transcript of a conversation for export/share.
enum ChatExport {
    static func transcript(title: String, lines: [(sender: String, time: String, body: String)]) -> String {
        var out = "Chat export — \(title)\n\n"
        for l in lines {
            out += "[\(l.time)] \(l.sender): \(l.body)\n"
        }
        return out
    }
}

// MARK: - Secured (locked + hidden) conversations

enum ChatLockStore {
    static func locked() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "chat.locked") ?? []) }
    static func isLocked(_ id: String) -> Bool { locked().contains(id) }
    static func setLocked(_ id: String, _ on: Bool) {
        var s = locked()
        if on { s.insert(id) } else { s.remove(id) }
        UserDefaults.standard.set(Array(s), forKey: "chat.locked")
    }
}

enum BiometricAuth {
    /// Prompts Face ID / Touch ID (passcode fallback). Returns true on success.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

// MARK: - Advanced chat privacy (per-conversation)

enum ChatPrivacyStore {
    static func isOn(_ id: String) -> Bool { UserDefaults.standard.bool(forKey: "chat.advprivacy.\(id)") }
    static func setOn(_ id: String, _ on: Bool) { UserDefaults.standard.set(on, forKey: "chat.advprivacy.\(id)") }
    static func label(_ id: String) -> String { isOn(id) ? "On" : "Off" }
}

// MARK: - Disappearing messages (per-conversation TTL)

enum ChatDisappearStore {
    /// Duration options in seconds (0 = Off), matching WhatsApp.
    static let options: [(label: String, seconds: TimeInterval)] = [
        ("Off", 0),
        ("24 hours", 86_400),
        ("7 days", 604_800),
        ("90 days", 7_776_000),
    ]

    static func ttl(_ id: String) -> TimeInterval {
        UserDefaults.standard.double(forKey: "chat.disappear.\(id)")
    }
    static func setTTL(_ id: String, _ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: "chat.disappear.\(id)")
    }
    static func label(_ id: String) -> String {
        let t = ttl(id)
        return options.first { $0.seconds == t }?.label ?? "Off"
    }

    /// Filters out messages older than the conversation's TTL (view-level
    /// disappearing). `date` extracts each item's timestamp.
    static func filter<T>(_ items: [T], convId: String, date: (T) -> Date?) -> [T] {
        let t = ttl(convId)
        guard t > 0 else { return items }
        let cutoff = Date().addingTimeInterval(-t)
        return items.filter { (date($0) ?? .distantFuture) >= cutoff }
    }

    // MARK: Shared state (chat_disappear_settings)
    //
    // The TTL used to live only in this device's UserDefaults, which made
    // the feature a private view filter: the other participant's client
    // never learned it, so their outgoing messages carried no expires_at
    // and their screen hid nothing. The server table makes the setting
    // conversation state — anyone sets it, everyone applies it, and the
    // pg_cron sweep (migration 084) deletes expired rows for real.

    /// The server key every participant computes identically for a DM.
    static func dmServerKey(_ a: String, _ b: String) -> String {
        "dm:" + [a, b].sorted().joined(separator: "|")
    }

    private struct SettingRow: Decodable {
        let convKey: String
        let ttlSeconds: Double
        enum CodingKeys: String, CodingKey {
            case convKey = "conv_key"
            case ttlSeconds = "ttl_seconds"
        }
    }

    /// Pulls every conversation TTL for the property and mirrors it into
    /// the local store. DM keys ("dm:a|b") map back to the peer's name.
    static func syncFromServer(propertyId: UUID, myName: String) async {
        let rows: [SettingRow]? = try? await supabase
            .from("chat_disappear_settings")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .execute()
            .value
        guard let rows else { return }
        for row in rows {
            let localId: String
            if row.convKey.hasPrefix("dm:") {
                let names = row.convKey.dropFirst(3).split(separator: "|").map(String.init)
                guard let peer = names.first(where: { $0 != myName }) ?? names.first else { continue }
                localId = peer
            } else {
                localId = row.convKey
            }
            setTTL(localId, row.ttlSeconds)
        }
    }

    /// Persists a TTL change so every participant's client picks it up.
    /// MainActor because it reads PropertyService.activePropertyId; callers
    /// are button actions, which already run there.
    @MainActor
    static func pushToServer(serverKey: String, seconds: TimeInterval) {
        guard let pid = PropertyService.activePropertyId,
              let uid = supabase.auth.currentSession?.user.id else { return }
        struct Payload: Encodable {
            let property_id: String
            let conv_key: String
            let ttl_seconds: Int
            let updated_by: String
        }
        let payload = Payload(property_id: pid.uuidString, conv_key: serverKey,
                              ttl_seconds: Int(seconds), updated_by: uid.uuidString)
        Task {
            _ = try? await supabase
                .from("chat_disappear_settings")
                .upsert(payload, onConflict: "property_id,conv_key")
                .execute()
        }
    }
}

// MARK: - Tone preview + picker

enum ChatTonePreview {
    // Short iOS system sounds used as previews. Each id is a distinct built-in
    // alert so the user can tell the options apart before saving.
    private static let alertIDs: [String: SystemSoundID] = [
        "Default": 1007, "Note": 1005, "Chime": 1008, "Glass": 1009, "Bamboo": 1013
    ]
    private static let callIDs: [String: SystemSoundID] = [
        "Default": 1151, "Classic": 1152, "Reflection": 1153, "Radar": 1154
    ]
    static func play(_ name: String, isCall: Bool) {
        guard name != "None" else { return }
        // Route through a playback session so the preview is audible even with
        // the ringer off / after recording a voice message.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let id = (isCall ? callIDs[name] : alertIDs[name]) ?? 1007
        AudioServicesPlaySystemSound(id)
    }
}

/// Tone list where tapping a row plays a preview and selects it. The selection
/// binding is persisted by the parent's onChange, so there is no separate save.
/// The curated classics come first; beneath them, every real Apple tone found
/// on the device (ringtones for calls, modern alert tones otherwise).
