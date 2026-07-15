import Foundation
import Supabase

/// The running build number (CFBundleVersion), stamped into the realtime
/// diagnostic banner so a FAIL/degraded string reveals EXACTLY which build
/// produced it — ending the "are you actually on the new build?" ambiguity.
let appBuildTag: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"

// MARK: - Broadcast payload access (the fix for "bcast:DEAD")
//
// supabase-swift (v2.51) hands every `onBroadcast(event:) { json in … }`
// closure the FULL Phoenix broadcast envelope — literally
// `{"event": "typing", "payload": { … the fields we sent … }, "type": "broadcast"}`
// — NOT the inner payload. Confirmed in `RealtimeChannelV2.triggerBroadcast`,
// which routes on `payload["event"]` and passes that same `payload` straight to
// the callback.
//
// So reading `json["name"]` (top level) always returned nil: the value lives at
// `json["payload"]["name"]`. That single level of nesting silently killed EVERY
// realtime broadcast the app relies on — typing, recording, and the dm_new /
// msg_new delivery pings — and the post-subscribe self-test that probes them,
// which is exactly the `socket:connected chan:subscribed bcast:DEAD` state: the
// channel joins fine, but no broadcast ever parses.
//
// These helpers read from the nested payload first, then fall back to the top
// level, so the app is correct on today's library AND on any future version
// that decides to unwrap the envelope for us.

/// A string field sent inside a broadcast, resolved from the nested payload
/// first and the top level second — robust to both envelope shapes.
func broadcastString(_ json: [String: AnyJSON], _ key: String) -> String? {
    if case let .object(inner)? = json["payload"],
       case let .string(value)? = inner[key] { return value }
    if case let .string(value)? = json[key] { return value }
    return nil
}
