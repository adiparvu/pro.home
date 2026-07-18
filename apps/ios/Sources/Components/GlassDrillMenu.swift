import SwiftUI

// MARK: - GlassDrillMenu — menu-in-menu on the NATIVE submenu
//
// The stacked card the user photographed in Photos (IMG_8580–8582) is the
// system's own submenu presentation: a nested `Menu` inside a menu on
// iOS 26 opens as a card OVER the dimmed parent, its header folds back,
// and a leaf choice dismisses the whole menu. Three hand-built rewrites
// chased that behavior; per Apple's WWDC26 guidance ("you get these
// components and interactions out of the box") the facets now ARE nested
// system menus: label + current value on the row, an inline Picker inside.
// The morph, the stacking, the fold-back and the dismissal contract are
// the system's — identical to Photos by construction.
//
// The facet vocabulary is unchanged, so pages keep building entries from
// the same `GlassPickerOption` arrays their flat sections use.

/// One facet the root list stacks into (Status, Category, …).
struct GlassDrillEntry: Identifiable {
    let id: String
    var icon: String? = nil
    /// The facet row's label AND the submenu's title.
    let title: LocalizedStringKey
    /// The current selection, shown as the row's subtitle.
    let valueLabel: String
    /// True when this facet is narrowed from its default (the trigger's
    /// accent dot aggregates it).
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
    /// GlassFilterActionRows the flat menus use.
    @ViewBuilder var footer: () -> Footer

    init(entries: [GlassDrillEntry], @ViewBuilder footer: @escaping () -> Footer) {
        self.entries = entries
        self.footer = footer
    }

    var body: some View {
        ForEach(entries) { entry in
            facetSubmenu(entry)
        }
        Divider()
        footer()
    }

    /// One facet: a nested system Menu whose row shows the facet title over
    /// its current value, and whose card holds the native checkmarked picker.
    private func facetSubmenu(_ entry: GlassDrillEntry) -> some View {
        // HIG (June 2026 revision): icons uniformly per group, or none.
        let showsIcons = !entry.options.isEmpty && entry.options.allSatisfy { $0.icon != nil }
        // The erased options carry closures, not a Binding — reconstruct one
        // over the option ids so the system Picker owns the checkmark.
        let selection = Binding<String>(
            get: { entry.options.first(where: \.isSelected)?.id ?? "" },
            set: { id in
                guard let option = entry.options.first(where: { $0.id == id }) else { return }
                HapticFeedback.selection()
                option.select()
            })
        return Menu {
            Picker(selection: selection) {
                ForEach(entry.options) { option in
                    Group {
                        if showsIcons, let icon = option.icon {
                            Label { Text(verbatim: option.title) } icon: { Image(systemName: icon) }
                        } else {
                            Text(verbatim: option.title)
                        }
                    }
                    .tag(option.id)
                }
            } label: { EmptyView() }
            .pickerStyle(.inline)
        } label: {
            // Two texts = the system's title + subtitle row anatomy — the
            // exact Photos facet row (current value under the facet name).
            Text(entry.title)
            Text(verbatim: entry.valueLabel)
            if let icon = entry.icon {
                Image(systemName: icon)
            }
        }
    }
}
