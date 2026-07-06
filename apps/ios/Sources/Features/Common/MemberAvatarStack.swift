import SwiftUI

struct MemberAvatarStack: View {
    let members: [FamilyMember]
    let ownerAvatarUrl: String?
    let ownerInitial: String
    let ringColor: Color
    var onTap: (() -> Void)? = nil

    private let size: CGFloat = 28
    private let overlap: CGFloat = 9

    private struct Item: Identifiable {
        let id: String
        let avatarUrl: String?
        let initial: String
        let color: Color
        let isOwner: Bool
    }

    private var items: [Item] {
        var list: [Item] = [Item(id: "owner", avatarUrl: ownerAvatarUrl, initial: ownerInitial, color: ringColor, isOwner: true)]
        for m in members.prefix(2) {
            list.append(Item(id: m.id.uuidString, avatarUrl: m.avatarUrl, initial: m.initials, color: m.swiftColor, isOwner: false))
        }
        return list
    }

    private var extraCount: Int { max(0, members.count - 2) }

    var body: some View {
        Button { onTap?() } label: {
            ZStack(alignment: .leading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    avatarCircle(item)
                        .offset(x: CGFloat(idx) * (size - overlap))
                        .zIndex(Double(items.count - idx))
                }
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .background(.gray.opacity(0.8), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                        .offset(x: CGFloat(items.count) * (size - overlap))
                }
            }
            .frame(width: CGFloat(items.count) * (size - overlap) + overlap + (extraCount > 0 ? size - overlap : 0),
                   height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Family members")
    }

    private func avatarCircle(_ item: Item) -> some View {
        Group {
            if let urlStr = item.avatarUrl, let url = URL(string: urlStr) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initialCircle(item)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialCircle(item)
            }
        }
        .overlay(Circle().strokeBorder(item.color.opacity(item.isOwner ? 1.0 : 0.7), lineWidth: 2))
        .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
    }

    private func initialCircle(_ item: Item) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [item.color, item.color.opacity(0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(item.initial)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Group header avatar (single circle: group photo, else a montage)

/// One circular group avatar for the chat header. Shows the uploaded group
/// photo when set; otherwise composes a montage of the owner + members'
/// avatars, like WhatsApp's default group icon.
struct GroupHeaderAvatar: View {
    let members: [FamilyMember]
    var photoUrl: String?
    var ownerAvatarUrl: String?
    var ownerInitial: String
    var ringColor: Color
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
            .overlay(Circle().strokeBorder(ringColor.opacity(0.9), lineWidth: 2))
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
                    else { initialBadge(ownerInitial, ringColor, s) }
                }
            } else {
                initialBadge(ownerInitial, ringColor, s)
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
                .font(.system(size: s * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: s, height: s)
    }
}

// MARK: - Ring color helper

func avatarRingColor(for name: String) -> Color {
    if name.hasPrefix("#") { return Color(hex: name) ?? .blue }
    switch name {
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
