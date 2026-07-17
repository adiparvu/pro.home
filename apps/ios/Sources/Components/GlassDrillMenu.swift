import SwiftUI

// MARK: - GlassDrillMenu — inline expanding submenus (the iOS 27 way)
//
// The native iOS submenu (the Photos library filter, IMG_8576) is NOT a
// slide-to-a-new-page drill: a facet row like "Tipuri multimedia ⌄" EXPANDS
// its options inline, right below itself, indented, with the chevron rotating
// to point down. The parent list stays; the card grows and shrinks. This
// mirrors that exactly — for pages whose one circle would otherwise stack
// four+ filter sections in a flat scroll (Inventory: Status / Category /
// Location / Sort + share/print), each facet becomes a disclosure row that
// shows its current value collapsed and reveals its options when tapped.
//
// One facet is open at a time (accordion). Selecting an option applies it and
// collapses back to the compact root, so several facets can be set in one
// visit; tapping away closes the whole menu. The card is sized to its content
// by the hosting GlassFilterButton, so expanding grows it downward from the
// trigger with a spring — no re-anchor jump (that was a scroll re-measure
// artifact, IMG_8561; a discrete expand is not that). Reduce Motion is honored.

/// One facet the root list expands into (Status, Category, …).
struct GlassDrillEntry: Identifiable {
    let id: String
    var icon: String? = nil
    /// The disclosure row's label.
    let title: LocalizedStringKey
    /// The current selection, shown greyed on the row while collapsed.
    let valueLabel: String
    /// Accent dot when this facet is narrowed from its default.
    var isNarrowed: Bool = false
    let options: [GlassDrillOption]

    /// Builds a facet from the same `GlassPickerOption` array a flat
    /// `GlassFilterSection` would use, so a page keeps one option vocabulary.
    static func facet<Value: Hashable>(
        id: String,
        icon: String? = nil,
        title: LocalizedStringKey,
        options: [GlassPickerOption<Value>],
        selection: Binding<Value>,
        isNarrowed: Bool
    ) -> GlassDrillEntry {
        let current = options.first { $0.value == selection.wrappedValue }
        return GlassDrillEntry(
            id: id, icon: icon, title: title,
            valueLabel: current?.title ?? "",
            isNarrowed: isNarrowed,
            options: options.map { option in
                GlassDrillOption(
                    id: String(describing: option.value),
                    icon: option.icon, title: option.title, count: option.count,
                    isSelected: option.value == selection.wrappedValue,
                    select: { selection.wrappedValue = option.value })
            })
    }
}

struct GlassDrillOption: Identifiable {
    let id: String
    var icon: String? = nil
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let select: () -> Void
}

struct GlassDrillMenu<Footer: View>: View {
    let entries: [GlassDrillEntry]
    /// Trailing one-shot rows (share/print) below the facets — the same
    /// GlassFilterActionRows the flat menus use, which dismiss the whole menu.
    @ViewBuilder var footer: () -> Footer

    /// The single expanded facet, or nil when all are collapsed (accordion).
    @State private var openId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(entries: [GlassDrillEntry], @ViewBuilder footer: @escaping () -> Footer) {
        self.entries = entries
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                Button {
                    HapticFeedback.impact(.light)
                    openId = (openId == entry.id) ? nil : entry.id
                } label: {
                    GlassDrillDisclosureRow(entry: entry, isOpen: openId == entry.id)
                }
                .buttonStyle(.plain)

                if openId == entry.id {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entry.options) { option in
                            Button {
                                HapticFeedback.selection()
                                option.select()
                                // Apply and collapse — the row now shows the
                                // new value; adjust another facet or tap away.
                                openId = nil
                            } label: {
                                GlassPopoverRow(icon: option.icon, title: option.title,
                                                count: option.count, isSelected: option.isSelected)
                                    // Inset so the options read as children of
                                    // the facet above them (the Photos look).
                                    .padding(.leading, AppSpacing.md)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity)
                }

                if entry.id != entries.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
            footer()
        }
        .frame(width: 288)
        .animation(reduceMotion ? nil : AppMotion.springy, value: openId)
    }
}

// MARK: - Disclosure row

/// A facet's row: icon + title (left), current value + a chevron that rotates
/// down when the facet's options are expanded inline below it.
private struct GlassDrillDisclosureRow: View {
    let entry: GlassDrillEntry
    let isOpen: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let icon = entry.icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOpen ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
            }
            Text(entry.title)
                .font(AppFont.scaled(15, weight: isOpen ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if entry.isNarrowed && !isOpen {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
            Spacer(minLength: AppSpacing.md)
            if !isOpen {
                Text(verbatim: entry.valueLabel)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // chevron.right rotated 90° points down — the expanded disclosure
            // indicator (Apple's ⌄), so the same glyph reads both states.
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(12, weight: .semibold))
                // Ternary needs one concrete style type: Color on both sides
                // (`.tertiary` alone is a ShapeStyle, not a Color).
                .foregroundStyle(isOpen ? Color.accentColor
                                        : Color.primary.opacity(AppOpacity.disabled))
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}
