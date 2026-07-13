import SwiftUI

// MARK: - Group header avatar (single circle: group photo, else a montage)

/// One circular group avatar for the chat header. Shows the uploaded group
/// photo when set; otherwise composes a montage of the owner + members'
/// avatars, like WhatsApp's default group icon.
struct GroupHeaderAvatar: View {
    let members: [FamilyMember]
    var photoUrl: String?
    var ownerAvatarUrl: String?
    var ownerInitial: String
    var size: CGFloat = 34
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            ZStack {
                if let urlStr = photoUrl, let url = URL(string: urlStr) {
                    StorageImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else { montage }
                    }
                } else {
                    montage
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Group info")
    }

    @ViewBuilder private var montage: some View {
        if let first = members.first {
            let s = size * 0.64
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12))
                memberCircle(first, s)
                    .offset(x: size * 0.16, y: size * 0.16)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1)
                        .frame(width: s, height: s)
                        .offset(x: size * 0.16, y: size * 0.16))
                ownerCircle(s)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .offset(x: -size * 0.16, y: -size * 0.16)
            }
        } else {
            ownerCircle(size)
        }
    }

    private func ownerCircle(_ s: CGFloat) -> some View {
        Group {
            if let urlStr = ownerAvatarUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { initialBadge(ownerInitial, .accentColor, s) }
                }
            } else {
                initialBadge(ownerInitial, .accentColor, s)
            }
        }
        .frame(width: s, height: s)
        .clipShape(Circle())
    }

    private func memberCircle(_ m: FamilyMember, _ s: CGFloat) -> some View {
        Group {
            if let urlStr = m.avatarUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { initialBadge(m.initials, m.swiftColor, s) }
                }
            } else {
                initialBadge(m.initials, m.swiftColor, s)
            }
        }
        .frame(width: s, height: s)
        .clipShape(Circle())
    }

    private func initialBadge(_ text: String, _ color: Color, _ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [color, color.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(text)
                .font(AppFont.scaled(s * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Assignee avatar

/// One task assignee's avatar, resolved across every identity form
/// `assignee_ids` can carry, so an account holder never renders as initials
/// while a profile photo exists (the owner has no roster row on a partner's
/// device — see AssigneePickerSheet). Resolution order:
///
/// 1. the `family_members` roster row (matched by roster id, then by name):
///    a linked account reads the LIVE `profiles` photo through
///    `MemberDirectory`, otherwise the row's `avatar_url` snapshot;
/// 2. `"user_<uuid>"` entries (account holders without a roster row): the
///    `profiles` directory by that auth user id;
/// 3. for an entry with no linked account, an unambiguous display-name match
///    in the directory (legacy assignments that stored an unlinked roster id
///    for someone who does hold an account);
/// 4. colored initials (`"custom_"` helpers and everyone unresolved).
///
/// Reading `MemberDirectory` inside `body` subscribes the view, so a newly
/// uploaded profile photo repaints every assignee row instantly; the
/// directory is already cached, so this adds no network work.
struct AssigneeAvatarView: View {
    let assigneeId: String?
    let name: String
    let members: [FamilyMember]
    var size: CGFloat = 30

    private var member: FamilyMember? {
        if let assigneeId, let uuid = UUID(uuidString: assigneeId),
           let match = members.first(where: { $0.id == uuid }) {
            return match
        }
        return members.first { $0.name == name }
    }

    /// Steps 2 + 3 of the resolution order — shared with other surfaces that
    /// hold an assignee-style id/name pair (e.g. the activity feed).
    static func directoryAvatarURL(assigneeId: String?, name: String) -> URL? {
        if let assigneeId, assigneeId.hasPrefix("user_"),
           let uid = UUID(uuidString: String(assigneeId.dropFirst("user_".count))),
           let url = MemberDirectory.shared.avatarURL(for: uid) {
            return url
        }
        guard assigneeId?.hasPrefix("custom_") != true,
              let s = MemberDirectory.shared.entry(matchingName: name)?.avatarUrl,
              !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var resolvedAvatar: String? {
        let member = self.member
        if let s = MemberDirectory.shared.avatarString(userId: member?.userId,
                                                       fallback: member?.avatarUrl),
           !s.isEmpty {
            return s
        }
        guard member?.userId == nil else { return nil }
        return Self.directoryAvatarURL(assigneeId: assigneeId, name: name)?.absoluteString
    }

    var body: some View {
        if let urlStr = resolvedAvatar {
            StorageImage(source: urlStr) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { initials }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initials
        }
    }

    @ViewBuilder private var initials: some View {
        let color = member?.swiftColor ?? Color.brandPrimaryBlue
        let text = member?.initials ?? String(name.prefix(1)).uppercased()
        ZStack {
            Circle().fill(color.opacity(0.22))
            Text(verbatim: text)
                .font(AppFont.scaled(size * 0.4, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Ring color helper
//
// Despite the historical name, this is the shared name→Color mapping for the
// app accent (PRVIOApp/AppearanceView) and the Profile page's avatar ring.
// Chat surfaces no longer draw a ring.

func avatarRingColor(for name: String) -> Color {
    if name.hasPrefix("#") { return Color(hex: name) ?? .blue }
    switch name {
    // "auto" = the accent follows the living background's mood. Resolved
    // through the engine's last-published mood (nonisolated — this function
    // is also called from UIKit appearance setup off the main actor). Views
    // that show it live (root tint, AppearanceView) already read
    // `AppMoodEngine.shared.resolved` in their bodies, so they re-evaluate
    // this the moment the mood changes.
    case "auto":   return AppMood.lastPublished.palette.accent
    case "purple": return .purple
    case "green":  return Color(red: 0.25, green: 0.82, blue: 0.45)
    case "orange": return .orange
    case "pink":   return .pink
    case "gold":   return Color(red: 0.9, green: 0.7, blue: 0.15)
    case "red":    return .red
    case "teal":   return .teal
    default:       return .blue
    }
}
