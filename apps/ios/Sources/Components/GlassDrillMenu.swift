import SwiftUI

// MARK: - GlassDrillMenu — the stacked submenu (the real iOS 26 pattern)
//
// The native Photos filter menu (IMG_8580–8582) opens a submenu as a CARD
// STACKED OVER the parent: the parent card stays mounted behind, dimmed,
// its top rows peeking above; the child appears in front as its own glass
// card whose header row carries the facet title + a DOWN chevron — tapping
// that header collapses back to the parent. Parent rows point at their
// submenu with a plain RIGHT chevron (nothing rotates). Picking a leaf
// option applies the filter and dismisses the WHOLE menu, exactly as
// Photos does.
//
// For pages whose one circle would otherwise stack four+ filter sections
// in a flat scroll (Inventory: Status / Category / Location / Sort +
// share/print), each facet becomes such a row. The popover's height
// changes only at the discrete open/close moments (never continuously
// mid-gesture), so the re-anchor "page jump" of IMG_8561 — a scroll
// re-measure artifact — cannot return. Reduce Motion keeps only the fade.

/// One facet the root list stacks into (Status, Category, …).
struct GlassDrillEntry: Identifiable {
    let id: String
    var icon: String? = nil
    /// The root row's label AND the child card's header title.
    let title: LocalizedStringKey
    /// The current selection, shown greyed on the root row.
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

    /// The facet whose child card is stacked over the root, or nil.
    @State private var openId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    private let width: CGFloat = 288
    /// How far the child card sits below the root's top — the parent's first
    /// rows peek above it, exactly the Photos stack (IMG_8582).
    private let childInset: CGFloat = 64

    private var openEntry: GlassDrillEntry? { entries.first { $0.id == openId } }

    init(entries: [GlassDrillEntry], @ViewBuilder footer: @escaping () -> Footer) {
        self.entries = entries
        self.footer = footer
    }

    var body: some View {
        ZStack(alignment: .top) {
            rootList
                // The parent recedes behind the child: dimmed, untouchable,
                // still visibly THERE — the stack reads as depth, not as a
                // page swap.
                .opacity(openId == nil ? 1 : 0.45)
                .allowsHitTesting(openId == nil)
                .accessibilityHidden(openId != nil)

            if let entry = openEntry {
                childCard(entry)
                    .padding(.top, childInset)
                    .transition(reduceMotion
                                ? .opacity
                                : .scale(scale: 0.95, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(width: width)
        .animation(reduceMotion ? nil : AppMotion.springy, value: openId)
    }

    // MARK: Root

    private var rootList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                Button {
                    HapticFeedback.impact(.light)
                    openId = entry.id
                } label: {
                    GlassDrillRootRow(entry: entry)
                }
                .buttonStyle(.plain)
                if entry.id != entries.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
            footer()
        }
    }

    // MARK: Child card

    private func childCard(_ entry: GlassDrillEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticFeedback.impact(.light)
                openId = nil
            } label: {
                // The Photos child header: facet title + DOWN chevron —
                // the affordance that this card folds back into its parent.
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.title)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: AppSpacing.md)
                    Image(systemName: "chevron.down")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            Divider().padding(.horizontal, AppSpacing.lg)
            ForEach(entry.options) { option in
                Button {
                    HapticFeedback.selection()
                    option.select()
                    // A leaf choice applies and the WHOLE menu goes away —
                    // the Photos behavior; the trigger's accent dot and the
                    // page itself already show the result.
                    dismiss()
                } label: {
                    GlassPopoverRow(icon: option.icon, title: option.title,
                                    count: option.count, isSelected: option.isSelected)
                }
                .buttonStyle(.plain)
                if option.id != entry.options.last?.id {
                    Divider().padding(.leading, AppSpacing.lg)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
        // Its OWN glass card, stacked over the parent's surface — the same
        // family look as the outer menu chrome, one level higher.
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
    }
}

// MARK: - Root row

/// A facet's root row: icon + title (left), current value + a plain RIGHT
/// chevron (right) — pointing at the submenu it stacks open (IMG_8581).
private struct GlassDrillRootRow: View {
    let entry: GlassDrillEntry

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let icon = entry.icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24)
            }
            Text(entry.title)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if entry.isNarrowed {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
            Spacer(minLength: AppSpacing.md)
            Text(verbatim: entry.valueLabel)
                .font(AppFont.scaled(14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}
