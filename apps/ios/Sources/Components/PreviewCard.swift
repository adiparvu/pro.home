import SwiftUI

// MARK: - PreviewCard — THE context-menu (long-press) preview card
//
// One reusable card for every `contextMenu(preview:)` surface (conversations,
// documents, plants, members, …), matching the quality bar set by the tasks'
// TaskGradientCard preview: adaptive Liquid Glass, an identity header
// (icon/avatar + title + subtitle), up to four key–value rows, an optional
// footer of state chips, a dynamic accent-tinted shadow and a subtle top
// reflection. Surfaces feed it ONLY real model data — missing fields are
// omitted by simply not passing a row/chip, never replaced by placeholders.
//
// HONESTY CONSTRAINT (permanent — do not "improve" this away):
//   A `contextMenu(preview:)` view is rendered by UIKit in its own
//   system-managed presentation (a separate window/portal), outside the
//   SwiftUI hierarchy that hosts the source row. Therefore:
//   • `matchedGeometryEffect` CANNOT animate the row into the preview — the
//     two views never share a geometry namespace. The lift-and-morph you see
//     is the system's own transition; we neither fake nor promise a custom
//     row→preview hero animation.
//   • The haptic on open is played by the system. PreviewCard triggers none.
//   • The preview is a non-interactive snapshot presented by the system;
//     don't put buttons or live gestures in it.

// MARK: - Row / chip models

/// One key–value line of the card. `label` is optional for values that are
/// self-explanatory next to their icon (e.g. "1.2 MB").
struct PreviewCardDetail {
    let icon: String
    var label: Text? = nil
    let value: Text
}

/// One footer state chip (e.g. unread count, health status, "Favorite").
struct PreviewCardChip {
    var icon: String? = nil
    let text: Text
    var tint: Color = .accentColor
}

// MARK: - Card

struct PreviewCard<Avatar: View>: View {
    /// The card's fixed width — previews are presented centered by the
    /// system, so they don't track the row width. 340pt matches the task
    /// preview and fits every supported device.
    static var cardWidth: CGFloat { 340 }

    private let title: Text
    private let subtitle: Text?
    private let headerTrailing: Text?
    private let tint: Color
    private let details: [PreviewCardDetail]
    private let chips: [PreviewCardChip]
    private let socialLinks: [SocialLink]
    private let avatar: () -> Avatar

    init(title: Text,
         subtitle: Text? = nil,
         headerTrailing: Text? = nil,
         tint: Color = .accentColor,
         details: [PreviewCardDetail] = [],
         chips: [PreviewCardChip] = [],
         socialLinks: [SocialLink] = [],
         @ViewBuilder avatar: @escaping () -> Avatar) {
        self.title = title
        self.subtitle = subtitle
        self.headerTrailing = headerTrailing
        self.tint = tint
        // The card is a glance, not a detail page — cap at five rows.
        self.details = Array(details.prefix(5))
        self.chips = chips
        // Same rule as every other social surface: saved handles only.
        self.socialLinks = SocialLinksRow.displayable(socialLinks)
        self.avatar = avatar
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            header
            if !details.isEmpty {
                hairline
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                        row(detail)
                    }
                }
            }
            if !socialLinks.isEmpty {
                hairline
                // The preview is a system-rendered non-interactive snapshot
                // (see the honesty constraint above) — the discs show WHICH
                // networks are set; opening them lives on the full page.
                SocialLinksRow(links: socialLinks)
            }
            if !chips.isEmpty {
                hairline
                HStack(spacing: AppSpacing.xs) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        chipView(chip)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: Self.cardWidth, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xxl)
        // Subtle top reflection — a whisper of light, clipped to the card.
        .overlay(
            shape.fill(
                LinearGradient(colors: [Color.white.opacity(0.06), .clear],
                               startPoint: .top, endPoint: .center)
            )
            .allowsHitTesting(false)
        )
        .overlay(shape.strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5))
        // Dynamic shadow: carries the surface's accent, like the task card.
        .shadow(color: tint.opacity(0.22), radius: 24, y: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            avatar()
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    subtitle
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            if let headerTrailing {
                headerTrailing
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    private func row(_ detail: PreviewCardDetail) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: detail.icon)
                .font(AppFont.caption)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            if let label = detail.label {
                label
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            Spacer(minLength: AppSpacing.sm)
            detail.value
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func chipView(_ chip: PreviewCardChip) -> some View {
        HStack(spacing: 5) {
            if let icon = chip.icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(10, weight: .semibold))
                    .accessibilityHidden(true)
            }
            chip.text
                .font(AppFont.captionStrong)
                .lineLimit(1)
        }
        .foregroundStyle(chip.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(chip.tint.opacity(0.14), in: Capsule())
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 0.5)
    }
}
