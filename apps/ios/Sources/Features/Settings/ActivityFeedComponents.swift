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
/// row snapshot), the signed-in user's own profile photo for "You", the
/// profiles directory for account holders without a roster row (a
/// "user_<uuid>" event id, or an unambiguous name match) — with colored
/// initials as the only fallback.
struct ActivityAvatarView: View {
    let member: FamilyMember?
    /// Already display-resolved (localized "You" or the member's name).
    let fallbackName: String
    let isCurrentUser: Bool
    /// The event's raw member id (task assignees carry "user_<uuid>" for
    /// account holders without a roster row) — the strongest directory key.
    var memberId: String? = nil
    var size: CGFloat = 18

    private var accountAvatarURL: URL? {
        if isCurrentUser {
            if let url = MemberDirectory.shared.avatarURL(for: supabase.auth.currentSession?.user.id) {
                return url
            }
            // "You" is a localized label, never a directory name — don't
            // let a stray name match resolve someone else's photo.
            return nil
        }
        return AssigneeAvatarView.directoryAvatarURL(assigneeId: memberId, name: fallbackName)
    }

    var body: some View {
        if let member {
            MemberAvatar(member: member, size: size)
        } else if let url = accountAvatarURL {
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

// MARK: - Member popover row

/// One member row inside the aggregated filter popover (IMG_8547) — the
/// real avatar the old chips carried, on `GlassPopoverRow`'s exact rhythm
/// so it sits flush with the Period/Category rows above it: the 24pt
/// avatar occupies the same leading column as the SF-symbol rows' 24pt
/// icon frame, and the trailing checkmark mirrors selection identically.
struct ActivityMemberPopoverRow: View {
    /// Already display-resolved (localized "You" or the member's name).
    let name: String
    let member: FamilyMember?
    let isCurrentUser: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ActivityAvatarView(member: member,
                               fallbackName: name,
                               isCurrentUser: isCurrentUser,
                               size: 24)
            Text(verbatim: name)
                .font(AppFont.scaled(15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: AppSpacing.lg)
            Image(systemName: "checkmark")
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
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
                                           memberId: event.memberId,
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
                                               memberId: aggregate.memberId,
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
