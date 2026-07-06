import SwiftUI

// MARK: - Page search (magnifier + system search field)
//
// The uniform search pattern for list pages: a magnifier button in the
// page's toolbar presents the system `.searchable` field, which filters
// the page content live. Keep one @State pair per page:
//
//   @State private var showSearch = false
//   @State private var searchText = ""
//
//   SearchIconButton(isActive: $showSearch)          // header/toolbar
//   .searchable(text: $searchText, isPresented: $showSearch,
//               placement: .navigationBarDrawer(displayMode: .automatic))
//
// and filter the displayed collection with `matchesSearch`. The inline
// `PageSearchField` remains only for surfaces outside a navigation bar
// (the Digital Twin's floating map-search overlay).

struct SearchIconButton: View {
    @Binding var isActive: Bool
    /// Plain style matches toolbar icon rows; glass style matches custom
    /// headers built from round glass buttons.
    var style: Style = .toolbar

    enum Style { case toolbar, glass }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            switch style {
            case .toolbar:
                // Presents the system search field — the drawer runs its own
                // transition, so no explicit animation is needed here.
                isActive = true
            case .glass:
                // The map overlay still toggles its inline field. Short
                // ease-out so it feels instant — a springy toggle reads as
                // lag between the tap and the bar appearing.
                withAnimation(.easeOut(duration: 0.12)) { isActive.toggle() }
            }
        } label: {
            switch style {
            case .toolbar:
                Image(systemName: "magnifyingglass")
                    .font(AppFont.subheadline)
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .frame(width: 38, height: 32)
            case .glass:
                Image(systemName: "magnifyingglass")
                    .font(AppFont.headline)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
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
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
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
