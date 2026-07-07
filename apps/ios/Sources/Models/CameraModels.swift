import Foundation

// MARK: - Security cameras (device-local by design)
//
// RTSP/IP cameras are reached over the LAN through their HTTP snapshot
// endpoint (Hikvision ISAPI, Dahua CGI, …). The camera list is deliberately
// NOT synced to Supabase: internal IPs, endpoint paths and usernames are
// security-sensitive network configuration that belongs to this device and
// this household member only — a compromised account should never leak a
// map of the home's camera network. Passwords never touch this model at
// all: they live exclusively in the Keychain (SecretStore), keyed by the
// camera's id, marked WhenUnlockedThisDeviceOnly.

struct SecurityCamera: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// Source kind — "rtsp" for snapshot-polled IP cameras. (HomeKit
    /// accessories are discovered live via HMHomeManager, never persisted.)
    var kind: String = "rtsp"
    /// Full http(s) URL of the still-image endpoint the user entered,
    /// e.g. "http://192.168.1.64/ISAPI/Streaming/channels/101/picture".
    /// Must not embed credentials — auth is handled per-request.
    var snapshotURL: String
    var username: String?
    var notes: String?
    var createdAt: Date = Date()
}

// MARK: - Local store

/// UserDefaults-backed persistence for the camera list. Small (a handful of
/// entries), read once at launch, written on every mutation — no reason for
/// anything heavier, and keeping it out of Supabase is a design decision
/// (see header comment), not an omission.
enum CameraStore {
    static let key = "prvio.cameras.v1"

    static func load() -> [SecurityCamera] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SecurityCamera].self, from: data)) ?? []
    }

    static func save(_ cameras: [SecurityCamera]) {
        guard let data = try? JSONEncoder().encode(cameras) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
