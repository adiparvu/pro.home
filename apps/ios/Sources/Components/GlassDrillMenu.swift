import SwiftUI

// MARK: - GlassDrillMenu — one level of drill-in inside the glass menu
//
// For pages whose single circle would otherwise host four+ filter sections
// stacked in one scroll (Inventory: Status / Category / Location / Sort +
// share/print), a flat popover reads as a wall. This presents the SAME
// content as the native iOS 26 submenu does: a compact root list of facets,
// each showing its current value, that slides — within the same glass card —
// to a page of options and back.
//
// The height is LOCKED to the root page's natural height (measured once from
// a hidden copy) and every page scrolls inside that fixed frame. A drill-in
// therefore never changes the popover's height, so it can't reintroduce the
// re-anchor "page jump" the flat menu carefully avoids (IMG_8561). Selecting
// an option applies it and slides back to root, so several facets can be set
// in one visit; tapping away closes the whole menu.

/// One facet the root list drills into (Status, Category, …).
struct GlassDrillEntry: Identifiable {
    let id: String
    var icon: String? = nil
    /// Row label AND the submenu's back-header title.
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
    /// Trailing one-shot rows (share/print) that live on the root page below
    /// the facets — GlassFilterActionRows, which dismiss the whole menu.
    @ViewBuilder var footer: () -> Footer

    @State private var openId: String?
    /// Root page's natural height, measured once and locked (see file note).
    @State private var lockedHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let width: CGFloat = 292
    private let maxHeight: CGFloat = 420
    private var height: CGFloat { lockedHeight ?? 320 }

    private var openEntry: GlassDrillEntry? { entries.first { $0.id == openId } }

    init(entries: [GlassDrillEntry], @ViewBuilder footer: @escaping () -> Footer) {
        self.entries = entries
        self.footer = footer
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            rootPage
                // Root slides a touch left and fades as the submenu covers it.
                .offset(x: openId == nil ? 0 : -width * 0.22)
                .opacity(openId == nil ? 1 : 0)
                .allowsHitTesting(openId == nil)
                .accessibilityHidden(openId != nil)
            if let entry = openEntry {
                submenuPage(entry)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(reduceMotion ? nil : AppMotion.springy, value: openId)
        // Hidden measuring copy: the root page's true height at this width,
        // read once and locked. The visible pages scroll inside the fixed
        // frame, so drilling never resizes the popover.
        .background(
            rootContent
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    lockedHeight = min(h, maxHeight)
                }
        )
    }

    // MARK: Pages

    private var rootPage: some View {
        ScrollView(showsIndicators: false) { rootContent }
            .frame(width: width, height: height)
            .scrollBounceBehavior(.basedOnSize)
    }

    private var rootContent: some View {
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
        .padding(.vertical, AppSpacing.xs)
    }

    private func submenuPage(_ entry: GlassDrillEntry) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    HapticFeedback.impact(.light)
                    openId = nil
                } label: {
                    GlassDrillBackHeader(title: entry.title)
                }
                .buttonStyle(.plain)
                Divider()
                ForEach(entry.options) { option in
                    Button {
                        HapticFeedback.selection()
                        option.select()
                        // Apply and slide back to root — the flexible flow
                        // (adjust another facet, or tap away to close).
                        openId = nil
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
        }
        .frame(width: width, height: height)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Rows

/// A root facet row: icon + title (left), current value + chevron (right),
/// an accent dot when the facet is narrowed from its default.
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
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}

/// The submenu's tappable back header: a leading chevron + the facet title,
/// mirroring an iOS navigation back control inside the same glass card.
private struct GlassDrillBackHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "chevron.left")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}
