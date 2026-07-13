import SwiftUI

// MARK: - Page search (system search field)
//
// The uniform search pattern for list pages is the plain system field —
// no toggle button. One @State per page:
//
//   @State private var searchText = ""
//
//   .searchable(text: $searchText,
//               placement: .navigationBarDrawer(displayMode: .automatic))
//
// Large-title pages use .automatic: the title arrives LARGE on entry and a
// pull-down reveals the field — the system pattern (Mail, Notes). A pinned
// .always drawer keeps the bar collapsed on entry (IMG_8070), so it's right
// only for inline-title picker sheets that are search-first. The earlier
// title flash blamed on .automatic came from the removed zoom transitions.
// Filter the displayed collection with `matchesSearch`. `SearchIconButton`
// and the inline `PageSearchField` remain only for surfaces outside a
// navigation bar (the Digital Twin's floating map-search overlay).

struct SearchIconButton: View {
    @Binding var isActive: Bool

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            // The map overlay toggles its inline field. Short ease-out so it
            // feels instant — a springy toggle reads as lag between the tap
            // and the bar appearing.
            withAnimation(.easeOut(duration: 0.12)) { isActive.toggle() }
        } label: {
            Image(systemName: "magnifyingglass")
                // Amber active state: this button serves only the Digital
                // Twin's floating overlay (see header comment), which wears
                // the smart-home warm skin.
                .font(AppFont.headline)
                .foregroundStyle(isActive ? Color.smartAmber : Color.primary.opacity(0.75))
                .frame(width: 40, height: 40)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }
}

struct PageSearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "Search…"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField(placeholder, text: $text)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                // Amber caret to match the twin's warm skin — the inline
                // field exists only for that overlay (see header comment).
                .tint(Color.smartAmber)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14)
        .onAppear { focused = true }
        // Fade in place: the move-transition shifted the whole page content,
        // which read as a laggy reveal.
        .transition(.opacity)
    }
}

extension String {
    /// Case- and diacritic-insensitive match used by page search filters.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
