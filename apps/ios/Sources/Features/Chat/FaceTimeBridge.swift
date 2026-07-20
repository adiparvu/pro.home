import SwiftUI
import UIKit
import Supabase

// MARK: - FaceTime bridge (in-chat calls, stage 1)
//
// Stage 1 of in-chat calling: the DM header bridges straight to the native
// FaceTime app via its URL schemes (`facetime-audio://` for audio,
// `facetime://` for video) — zero server infrastructure, and Apple's stack
// owns ringing, availability and the call UI end to end.
//
// Honesty contract: the header buttons render ONLY when a handle resolves
// for the peer (no dead controls). When a handle exists the buttons always
// render — whether the callee is actually reachable is FaceTime's call, not
// ours to guess.
//
// GROUP CHAT DELIBERATELY GETS NO CALL BUTTONS IN THIS STAGE: the
// `facetime://` URL scheme accepts exactly one callee, so a multi-party
// FaceTime cannot be started from a URL. Stage 2 (LiveKit-backed in-app
// calls) is the plan for group conversations.
enum FaceTimeBridge {

    // MARK: Handle resolution

    /// The best FaceTime handle for a DM peer, in strict priority order:
    ///
    /// 1. **Account e-mail** — the peer's `profiles.email` (the address they
    ///    sign in to PRVIO with; household-readable per migration 106, the
    ///    same source the Members > Accounts tab shows). Most likely to be
    ///    registered with FaceTime.
    /// 2. **Roster e-mail** — `family_members.email`, matched by user id
    ///    first, then by unique display name.
    /// 3. **Roster phone** — `family_members.phone`, same matching.
    ///
    /// Returns nil when no source yields a handle that forms a valid
    /// FaceTime URL — the caller must then show no call controls at all.
    @MainActor
    static func handle(for peer: ChatPeer?, member: FamilyMember?, roster: [FamilyMember]) async -> String? {
        // 1. Account e-mail (needs an auth user id to look up).
        if let userId = peer?.id, let email = await accountEmail(userId: userId),
           let handle = emailHandle(email) {
            return handle
        }
        let row = rosterRow(for: peer, member: member, roster: roster)
        // 2. Roster e-mail.
        if let email = row?.email, let handle = emailHandle(email) { return handle }
        // 3. Roster phone.
        if let phone = row?.phone, let handle = phoneHandle(phone) { return handle }
        return nil
    }

    // MARK: Calls

    @MainActor
    static func callAudio(_ handle: String) {
        guard let url = url(scheme: "facetime-audio", handle: handle) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    static func callVideo(_ handle: String) {
        guard let url = url(scheme: "facetime", handle: handle) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Private helpers

    /// The peer's roster row: the explicit member when the view already
    /// holds one, else a user-id match, else a UNIQUE display-name match
    /// (names drift and duplicate — an ambiguous match must never dial a
    /// different person).
    private static func rosterRow(for peer: ChatPeer?, member: FamilyMember?,
                                  roster: [FamilyMember]) -> FamilyMember? {
        if let member { return member }
        if let userId = peer?.id, let hit = roster.first(where: { $0.userId == userId }) {
            return hit
        }
        guard let name = peer?.displayName else { return nil }
        let hits = roster.filter { DirectMessage.nameMatches($0.name, name) }
        return hits.count == 1 ? hits.first : nil
    }

    /// The peer's account e-mail from `profiles` (readable within the
    /// household since migration 106). Best-effort: any failure just means
    /// falling through to the roster sources.
    private static func accountEmail(userId: UUID) async -> String? {
        struct Row: Decodable { let email: String? }
        let rows: [Row]? = try? await supabase
            .from("profiles")
            .select("email")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute().value
        return rows?.first?.email
    }

    /// A trimmed e-mail, kept only when it forms valid FaceTime URLs.
    private static func emailHandle(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), url(scheme: "facetime", handle: email) != nil,
              url(scheme: "facetime-audio", handle: email) != nil else { return nil }
        return email
    }

    /// Dialable digits (the `tel://` pattern used across the app), kept only
    /// when they form valid FaceTime URLs.
    private static func phoneHandle(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, url(scheme: "facetime", handle: digits) != nil,
              url(scheme: "facetime-audio", handle: digits) != nil else { return nil }
        return digits
    }

    private static func url(scheme: String, handle: String) -> URL? {
        URL(string: "\(scheme)://\(handle)")
    }
}

// MARK: - DM header call cluster

/// The trailing FaceTime cluster in the DM header — audio + video in one
/// floating glass capsule, visually identical to `ChatHeaderActions` (the
/// group chat's cluster) but wired straight to the FaceTime bridge.
/// Render it ONLY with a resolved handle (see the honesty contract above).
struct DMFaceTimeHeaderButtons: View {
    let handle: String

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticFeedback.impact(.light)
                FaceTimeBridge.callVideo(handle)
            } label: {
                Image(systemName: "video")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "call_facetime_video")))

            Button {
                HapticFeedback.impact(.light)
                FaceTimeBridge.callAudio(handle)
            } label: {
                Image(systemName: "phone")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "call_facetime_audio")))
        }
        // iOS 26 wraps toolbar items in system Liquid Glass — only pre-26
        // draws its own capsule (see chatToolbarCapsule).
        .chatToolbarCapsule()
    }
}
