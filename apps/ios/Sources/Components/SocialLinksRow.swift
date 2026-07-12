import SwiftUI

// MARK: - SocialLinksRow
//
// The one way saved social profiles are previewed anywhere in the app:
// a horizontal row with one platform-tinted disc per SAVED network — never
// a placeholder, never a dead icon. Tapping opens the profile through its
// https URL (which universal-links into the installed app when present).
// An entry that has a handle but no truthful destination — a WhatsApp
// value that isn't a phone number — renders as a visibly inert chip
// showing the stored handle instead of pretending to be a link.
//
// Iconography, colors and URL building all come from SocialLink itself
// (the same source the "Add Network" sheet draws from), so every surface
// stays consistent by construction.

struct SocialLinksRow: View {
    let links: [SocialLink]

    /// Only networks with a saved handle earn a spot in the row.
    static func displayable(_ links: [SocialLink]?) -> [SocialLink] {
        (links ?? []).filter { !$0.sanitizedHandle.isEmpty }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(Self.displayable(links)) { link in
                    if let url = link.openURL {
                        Button {
                            HapticFeedback.impact(.light)
                            UIApplication.shared.open(url)
                        } label: {
                            platformDisc(link)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(format: String(localized: "soc_open_profile_fmt"),
                                   link.platformLabel))
                    } else {
                        inertChip(link)
                    }
                }
            }
        }
    }

    // The 46pt tinted disc the member profile sheet established.
    private func platformDisc(_ link: SocialLink) -> some View {
        ZStack {
            Circle()
                .fill(link.platformColor.opacity(0.13))
                .frame(width: 46, height: 46)
            Image(systemName: link.platformIcon)
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(link.platformColor)
        }
    }

    /// Honest fallback: the network and its stored handle, not a button.
    private func inertChip(_ link: SocialLink) -> some View {
        HStack(spacing: 6) {
            Image(systemName: link.platformIcon)
                .font(AppFont.scaled(13, weight: .semibold))
            Text(link.sanitizedHandle)
                .font(AppFont.scaled(13))
                .lineLimit(1)
        }
        .foregroundStyle(link.platformColor.opacity(AppOpacity.emphasis))
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(link.platformColor.opacity(0.10), in: Capsule())
        .accessibilityLabel(
            String(format: String(localized: "soc_no_link_fmt"),
                   link.platformLabel, link.sanitizedHandle))
    }
}
