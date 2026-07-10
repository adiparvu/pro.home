import SwiftUI

// MARK: - Time text

/// The row timestamp: the real time when the source stored one, otherwise a
/// short locale-aware date ("Jul 7" / "7 iul.") — never a fabricated "00:00".
struct ActivityTimeText: View {
    let date: Date
    let hasTime: Bool

    var body: some View {
        Group {
            if hasTime {
                Text(date, format: .dateTime.hour().minute())
            } else {
                Text(AppDate.monthDay.string(from: date))
            }
        }
        .font(AppFont.caption2)
        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        .monospacedDigit()
    }
}

// MARK: - Avatar

/// The feed's member avatar: the real photo whenever one exists —
/// `MemberAvatar` for family members (live `MemberDirectory` photo, then the
/// row snapshot), the signed-in user's own profile photo for "You" — with
/// colored initials as the only fallback.
struct ActivityAvatarView: View {
    let member: FamilyMember?
    /// Already display-resolved (localized "You" or the member's name).
    let fallbackName: String
    let isCurrentUser: Bool
    var size: CGFloat = 18

    var body: some View {
        if let member {
            MemberAvatar(member: member, size: size)
        } else if isCurrentUser,
                  let url = MemberDirectory.shared.avatarURL(for: supabase.auth.currentSession?.user.id) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    initials
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.brandPrimaryBlue.opacity(AppOpacity.tintedFill))
            Text(String(fallbackName.prefix(1)).uppercased())
                .font(AppFont.scaled(size * 0.5, weight: .semibold))
                .foregroundStyle(Color.brandPrimaryBlue)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Member filter chip

/// A member filter chip — real avatar + name on the sanctioned filter-capsule
/// glass, matching `GlassFilterChip`'s selected/unselected treatment.
struct ActivityMemberChip: View {
    let name: String
    let member: FamilyMember?
    let isCurrentUser: Bool
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color {
        isSelected ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                ActivityAvatarView(member: member,
                                   fallbackName: name,
                                   isCurrentUser: isCurrentUser,
                                   size: 20)
                Text(verbatim: name)
                    .font(AppFont.scaled(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(tint)
            }
            .padding(.leading, AppSpacing.xs)
            .padding(.trailing, AppSpacing.base)
            .padding(.vertical, AppSpacing.xxs)
            .glassFilterCapsule(selected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Event row

/// One navigable feed row: module-colored icon on a subtly tinted circle,
/// title/subtitle, honest timestamp, real member avatar, and a quiet
/// disclosure chevron — tapping opens the object the event is about.
struct ActivityEventRow: View {
    let event: ActivityEvent
    let member: FamilyMember?
    let memberDisplayName: String
    let isCurrentUser: Bool
    let showsDivider: Bool
    /// True for rows revealed by expanding an aggregate — slightly inset and
    /// more compact to read as children of the aggregate above.
    var indented: Bool = false
    let onOpen: () -> Void

    private var iconSide: CGFloat { indented ? 30 : 36 }
    private var leadingInset: CGFloat { AppSpacing.base + (indented ? AppSpacing.lg : 0) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: event.icon)
                        .font(indented ? AppFont.subheadline : AppFont.body)
                        .foregroundStyle(event.color)
                        .frame(width: iconSide, height: iconSide)
                        .background(event.color.opacity(AppOpacity.tintedFill), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text(event.subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AppSpacing.sm)

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        ActivityTimeText(date: event.date, hasTime: event.hasTime)
                        ActivityAvatarView(member: member,
                                           fallbackName: memberDisplayName,
                                           isCurrentUser: isCurrentUser,
                                           size: 18)
                    }

                    Image(systemName: "chevron.right")
                        .font(AppFont.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, AppSpacing.base)
                .padding(.vertical, indented ? AppSpacing.sm : AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if showsDivider {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, leadingInset + iconSide + AppSpacing.md)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Aggregate row

/// A collapsed run of same-kind, same-member, same-day events
/// ("2 tasks completed" · "Garage Door, Mow lawn"). Tapping toggles the
/// individual rows below it; the chevron flips to mirror the state.
struct ActivityAggregateRow: View {
    let aggregate: ActivityAggregate
    let isExpanded: Bool
    let member: FamilyMember?
    let memberDisplayName: String
    let isCurrentUser: Bool
    let showsDivider: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: aggregate.icon)
                        .font(AppFont.body)
                        .foregroundStyle(aggregate.kind.color)
                        .frame(width: 36, height: 36)
                        .background(aggregate.kind.color.opacity(AppOpacity.tintedFill), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(aggregate.title)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text(aggregate.subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AppSpacing.sm)

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        if let newest = aggregate.events.first {
                            ActivityTimeText(date: newest.date, hasTime: newest.hasTime)
                        }
                        HStack(spacing: AppSpacing.xxs) {
                            ActivityAvatarView(member: member,
                                               fallbackName: memberDisplayName,
                                               isCurrentUser: isCurrentUser,
                                               size: 18)
                            Image(systemName: "chevron.down")
                                .font(AppFont.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? -180 : 0))
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if showsDivider {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, AppSpacing.base + 36 + AppSpacing.md)
            }
        }
    }
}
